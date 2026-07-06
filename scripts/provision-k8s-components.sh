#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  provision-k8s-components.sh <scope> [--bootstrap-platform-controllers]

Scopes:
  mongodb   Apply MongoDB operator, Kyverno policies, bootstrap secrets, and dev overlay.
  mongo     Alias of mongodb.
  signoz    Apply optional open-source SigNoz GitOps base only.
  operators Apply only operator Helm layer.
  policies  Apply only Kyverno policies.
  overlay   Apply only MongoDB dev overlay.
  all       Apply MongoDB scope, then SigNoz.

Examples:
  scripts/provision-k8s-components.sh signoz
  scripts/provision-k8s-components.sh mongodb
  scripts/provision-k8s-components.sh mongo
  scripts/provision-k8s-components.sh mongodb --bootstrap-platform-controllers
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCOPE="${1:-}"
MONGODB_CRD_NAME="perconaservermongodbs.psmdb.percona.com"
WAIT_TIMEOUT_SECONDS="${MONGODB_OPERATOR_READY_TIMEOUT_SECONDS:-180}"
BOOTSTRAP_PLATFORM_CONTROLLERS="false"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-EKS-boomi-runtime-cluster}"
EBS_CSI_ROLE_NAME="${EBS_CSI_ROLE_NAME:-AmazonEKS_EBS_CSI_DriverRole}"
EBS_CSI_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

MISSING_CRDS=()

record_missing_crd() {
  local crd_name="$1"
  local install_hint="$2"

  if kubectl get crd "$crd_name" >/dev/null 2>&1; then
    return 0
  fi

  MISSING_CRDS+=("$crd_name|$install_hint")
}

require_crd() {
  local crd_name="$1"
  local install_hint="$2"

  if kubectl get crd "$crd_name" >/dev/null 2>&1; then
    return 0
  fi

  echo "ERROR: required CRD not found: $crd_name" >&2
  echo "Current kubectl context: $(kubectl config current-context 2>/dev/null || echo unknown)" >&2
  echo "$install_hint" >&2
  exit 1
}

ensure_no_missing_crds() {
  local scope_name="$1"
  local current_context

  if [[ ${#MISSING_CRDS[@]} -eq 0 ]]; then
    return 0
  fi

  current_context="$(kubectl config current-context 2>/dev/null || echo unknown)"
  echo "ERROR: missing required CRDs for scope '$scope_name'." >&2
  echo "Current kubectl context: $current_context" >&2
  for entry in "${MISSING_CRDS[@]}"; do
    local crd_name="${entry%%|*}"
    local install_hint="${entry#*|}"
    echo "- $crd_name" >&2
    echo "  $install_hint" >&2
  done
  exit 1
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  fi
}

ensure_aws_role_with_policy() {
  local role_name="$1"
  local policy_arn="$2"
  local trust_policy_json="$3"
  local trust_file

  if ! aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    trust_file="$(mktemp)"
    printf '%s\n' "$trust_policy_json" > "$trust_file"
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "file://$trust_file" >/dev/null
    rm -f "$trust_file"
  fi

  aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" >/dev/null
}

wait_for_eks_addon_active() {
  local addon_name="$1"
  local deadline=$((SECONDS + 600))
  local addon_status

  while true; do
    addon_status="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" --query 'addon.status' --output text 2>/dev/null || echo MISSING)"
    case "$addon_status" in
      ACTIVE)
        return 0
        ;;
      DEGRADED|CREATE_FAILED|DELETE_FAILED|UPDATE_FAILED)
        echo "ERROR: addon '$addon_name' entered status '$addon_status'." >&2
        exit 1
        ;;
    esac
    if (( SECONDS >= deadline )); then
      echo "ERROR: timed out waiting for addon '$addon_name' to become ACTIVE (last status: $addon_status)." >&2
      exit 1
    fi
    sleep 10
  done
}

bootstrap_flux_controllers() {
  require_cmd helm
  require_cmd kubectl

  echo "Bootstrapping Flux controllers..."
  helm repo add fluxcd-community https://fluxcd-community.github.io/helm-charts >/dev/null
  helm repo update >/dev/null
  kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  helm upgrade --install flux2 fluxcd-community/flux2 -n flux-system
}

bootstrap_kyverno() {
  require_cmd helm
  require_cmd kubectl

  echo "Bootstrapping Kyverno..."
  helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
  helm repo update >/dev/null
  kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  helm upgrade --install kyverno kyverno/kyverno -n kyverno
}

bootstrap_cert_manager() {
  require_cmd helm
  require_cmd kubectl

  echo "Bootstrapping cert-manager..."
  helm repo add jetstack https://charts.jetstack.io >/dev/null
  helm repo update >/dev/null
  kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --set crds.enabled=true
}

bootstrap_ebs_csi_driver() {
  local addon_name="aws-ebs-csi-driver"
  local addon_version
  local role_arn
  local trust_policy_json='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

  require_cmd aws
  require_cmd kubectl

  echo "Bootstrapping AWS EBS CSI driver addon..."
  addon_version="$(aws eks describe-addon-versions --addon-name "$addon_name" --kubernetes-version "$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.version' --output text)" --query 'addons[0].addonVersions[0].addonVersion' --output text)"
  ensure_aws_role_with_policy "$EBS_CSI_ROLE_NAME" "$EBS_CSI_POLICY_ARN" "$trust_policy_json"
  role_arn="$(aws iam get-role --role-name "$EBS_CSI_ROLE_NAME" --query 'Role.Arn' --output text)"

  if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" >/dev/null 2>&1; then
    aws eks update-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name "$addon_name" \
      --addon-version "$addon_version" \
      --service-account-role-arn "$role_arn" \
      --resolve-conflicts OVERWRITE >/dev/null
  else
    aws eks create-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name "$addon_name" \
      --addon-version "$addon_version" \
      --service-account-role-arn "$role_arn" \
      --resolve-conflicts OVERWRITE >/dev/null
  fi

  wait_for_eks_addon_active "$addon_name"
}

preflight_scope() {
  if [[ "$BOOTSTRAP_PLATFORM_CONTROLLERS" == "true" ]]; then
    case "$1" in
      mongodb|mongo)
        bootstrap_ebs_csi_driver
        bootstrap_flux_controllers
        bootstrap_kyverno
        bootstrap_cert_manager
        ;;
      signoz|operators)
        bootstrap_flux_controllers
        ;;
      policies)
        bootstrap_kyverno
        ;;
    esac
  fi

  MISSING_CRDS=()
  case "$1" in
    mongodb|mongo)
      record_missing_crd "helmreleases.helm.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRelease CRD is missing), then rerun this command."
      record_missing_crd "helmrepositories.source.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRepository CRD is missing), then rerun this command."
      record_missing_crd "clusterpolicies.kyverno.io" \
        "Install Kyverno first (ClusterPolicy CRD is missing), then rerun this command."
      record_missing_crd "certificates.cert-manager.io" \
        "Install cert-manager first (Certificate CRD is missing), then rerun this command."
      record_missing_crd "issuers.cert-manager.io" \
        "Install cert-manager first (Issuer CRD is missing), then rerun this command."
      if ! kubectl get csidriver ebs.csi.aws.com >/dev/null 2>&1; then
        MISSING_CRDS+=("ebs.csi.aws.com|Install the AWS EBS CSI driver addon first, then rerun this command.")
      fi
      ensure_no_missing_crds "$1"
      ;;
    signoz|operators)
      record_missing_crd "helmreleases.helm.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRelease CRD is missing), then rerun this command."
      record_missing_crd "helmrepositories.source.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRepository CRD is missing), then rerun this command."
      ensure_no_missing_crds "$1"
      ;;
    policies)
      record_missing_crd "clusterpolicies.kyverno.io" \
        "Install Kyverno first (ClusterPolicy CRD is missing), then rerun this command."
      ensure_no_missing_crds "$1"
      ;;
  esac
}

if [[ -z "$SCOPE" ]]; then
  usage
  exit 1
fi

shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap-platform-controllers)
      BOOTSTRAP_PLATFORM_CONTROLLERS="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

apply_operators() {
  require_crd "helmreleases.helm.toolkit.fluxcd.io" \
    "Install Flux source/helm controllers first (HelmRelease CRD is missing), then rerun this command."
  require_crd "helmrepositories.source.toolkit.fluxcd.io" \
    "Install Flux source/helm controllers first (HelmRepository CRD is missing), then rerun this command."
  kubectl apply -k "$ROOT_DIR/gitops/operators/base"
}

apply_policies() {
  require_crd "clusterpolicies.kyverno.io" \
    "Install Kyverno first (ClusterPolicy CRD is missing), then rerun this command."
  kubectl apply -k "$ROOT_DIR/policies/kyverno"
}

apply_overlay() {
  kubectl apply -k "$ROOT_DIR/k8s/overlays/dev"
}

apply_signoz() {
  kubectl apply -k "$ROOT_DIR/gitops/signoz/base"
}

wait_for_mongodb_crd() {
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

  echo "Waiting for MongoDB CRD $MONGODB_CRD_NAME (timeout: ${WAIT_TIMEOUT_SECONDS}s)..."
  while ! kubectl get crd "$MONGODB_CRD_NAME" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: MongoDB CRD '$MONGODB_CRD_NAME' not found within ${WAIT_TIMEOUT_SECONDS}s." >&2
      echo "Hint: ensure Flux and the operator HelmRelease are healthy before applying the overlay." >&2
      exit 1
    fi
    sleep 5
  done
}

case "$SCOPE" in
  mongodb|mongo)
    preflight_scope "$SCOPE"
    apply_operators
    "$ROOT_DIR/scripts/bootstrap-dev-secrets.sh"
    apply_policies
    wait_for_mongodb_crd
    apply_overlay
    ;;
  signoz)
    preflight_scope "$SCOPE"
    apply_signoz
    ;;
  operators)
    preflight_scope "$SCOPE"
    apply_operators
    ;;
  policies)
    preflight_scope "$SCOPE"
    apply_policies
    ;;
  overlay)
    apply_overlay
    ;;
  all)
    if [[ "$BOOTSTRAP_PLATFORM_CONTROLLERS" == "true" ]]; then
      "$0" mongodb --bootstrap-platform-controllers
      "$0" signoz --bootstrap-platform-controllers
    else
      "$0" mongodb
      "$0" signoz
    fi
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Error: unknown scope '$SCOPE'. Expected one of: mongodb, mongo, signoz, operators, policies, overlay, all" >&2
    usage
    exit 1
    ;;
esac

echo "Completed Kubernetes scope: $SCOPE"
