#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  provision-k8s-components.sh <scope> [--bootstrap-platform-controllers]

Scopes:
  mongodb    Apply MongoDB operator, Kyverno policies, bootstrap secrets, and dev overlay.
  mongo      Alias of mongodb.
  postgresql Apply CNPG operator, Kyverno policies, and both core/brand dev Cluster overlays.
  postgresql-coredb   Apply only the core CNPG Cluster overlay (namespace coredb) — independent of brand.
  postgresql-branddb  Apply only the brand CNPG Cluster overlay (namespace branddb) — independent of core.
  signoz     Apply optional open-source SigNoz GitOps base only.
  operators  Apply only operator Helm layer.
  policies   Apply only Kyverno policies.
  overlay    Apply only MongoDB dev overlay.
  all        Apply MongoDB scope, then SigNoz.

Examples:
  scripts/provision-k8s-components.sh signoz
  scripts/provision-k8s-components.sh mongodb
  scripts/provision-k8s-components.sh mongo
  scripts/provision-k8s-components.sh postgresql
  scripts/provision-k8s-components.sh postgresql-coredb
  scripts/provision-k8s-components.sh postgresql-branddb
  scripts/provision-k8s-components.sh mongodb --bootstrap-platform-controllers
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCOPE="${1:-}"
MONGODB_CRD_NAME="perconaservermongodbs.psmdb.percona.com"
POSTGRESQL_CRD_NAME="clusters.postgresql.cnpg.io"
WAIT_TIMEOUT_SECONDS="${MONGODB_OPERATOR_READY_TIMEOUT_SECONDS:-180}"
SIGNOZ_READY_TIMEOUT_SECONDS="${SIGNOZ_READY_TIMEOUT_SECONDS:-600}"
BOOTSTRAP_PLATFORM_CONTROLLERS="false"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-EKS-boomi-runtime-cluster}"
EBS_CSI_ROLE_NAME="${EBS_CSI_ROLE_NAME:-AmazonEKS_EBS_CSI_DriverRole}"
EBS_CSI_POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
EBS_CSI_CONTROLLER_SERVICE_ACCOUNT="ebs-csi-controller-sa"
EKS_POD_IDENTITY_AGENT_ADDON_NAME="eks-pod-identity-agent"

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

  trust_file="$(mktemp)"
  printf '%s\n' "$trust_policy_json" > "$trust_file"

  if ! aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "file://$trust_file" >/dev/null
  else
    aws iam update-assume-role-policy --role-name "$role_name" --policy-document "file://$trust_file" >/dev/null
  fi

  rm -f "$trust_file"

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

wait_for_eks_addon_deleted() {
  local addon_name="$1"
  local deadline=$((SECONDS + 600))
  local addon_status

  while true; do
    if ! aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" >/dev/null 2>&1; then
      return 0
    fi

    addon_status="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" --query 'addon.status' --output text 2>/dev/null || echo MISSING)"
    if [[ "$addon_status" == "DELETE_FAILED" ]]; then
      echo "ERROR: addon '$addon_name' entered status 'DELETE_FAILED'." >&2
      exit 1
    fi

    if (( SECONDS >= deadline )); then
      echo "ERROR: timed out waiting for addon '$addon_name' to be deleted (last status: $addon_status)." >&2
      exit 1
    fi

    sleep 10
  done
}

has_cluster_oidc_provider() {
  local oidc_issuer
  local oidc_provider_path

  oidc_issuer="$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null || true)"
  if [[ -z "$oidc_issuer" || "$oidc_issuer" == "None" ]]; then
    return 1
  fi

  oidc_provider_path="${oidc_issuer#https://}"
  aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text | tr '\t' '\n' | grep -Fq "$oidc_provider_path"
}

get_cluster_oidc_issuer() {
  aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.identity.oidc.issuer' --output text
}

get_cluster_oidc_provider_arn() {
  local oidc_issuer
  local oidc_provider_path

  oidc_issuer="$(get_cluster_oidc_issuer)"
  oidc_provider_path="${oidc_issuer#https://}"
  aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text | tr '\t' '\n' | grep -F "$oidc_provider_path" | head -n 1
}

build_pod_identity_trust_policy_json() {
  cat <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}
EOF
}

build_irsa_trust_policy_json() {
  local oidc_issuer
  local oidc_provider_arn
  local oidc_provider_path

  oidc_issuer="$(get_cluster_oidc_issuer)"
  oidc_provider_arn="$(get_cluster_oidc_provider_arn)"
  oidc_provider_path="${oidc_issuer#https://}"

  cat <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"$oidc_provider_arn"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"$oidc_provider_path:sub":"system:serviceaccount:kube-system:$EBS_CSI_CONTROLLER_SERVICE_ACCOUNT","$oidc_provider_path:aud":"sts.amazonaws.com"}}}]}
EOF
}

bootstrap_pod_identity_agent() {
  local addon_name="$EKS_POD_IDENTITY_AGENT_ADDON_NAME"
  local addon_status="MISSING"
  local addon_version
  local current_version=""

  require_cmd aws

  echo "Ensuring EKS Pod Identity agent addon is installed..."
  addon_version="$(aws eks describe-addon-versions --addon-name "$addon_name" --kubernetes-version "$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.version' --output text)" --query 'addons[0].addonVersions[0].addonVersion' --output text)"

  if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" >/dev/null 2>&1; then
    addon_status="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" --query 'addon.status' --output text)"
    case "$addon_status" in
      CREATING|UPDATING)
        echo "Addon '$addon_name' is currently $addon_status; waiting for it to become ACTIVE..."
        wait_for_eks_addon_active "$addon_name"
        ;;
      DELETING)
        echo "ERROR: addon '$addon_name' is currently DELETING; wait for deletion to finish before rerunning bootstrap." >&2
        exit 1
        ;;
    esac

    current_version="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" --query 'addon.addonVersion' --output text)"
    if [[ "$current_version" == "$addon_version" ]]; then
      echo "EKS Pod Identity agent addon is already configured with version $addon_version."
      return 0
    fi

    aws eks update-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name "$addon_name" \
      --addon-version "$addon_version" \
      --resolve-conflicts OVERWRITE >/dev/null
  else
    aws eks create-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name "$addon_name" \
      --addon-version "$addon_version" \
      --resolve-conflicts OVERWRITE >/dev/null
  fi

  wait_for_eks_addon_active "$addon_name"
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
  local auth_mode="irsa"
  local addon_version
  local addon_status="MISSING"
  local current_role_arn=""
  local current_version=""
  local pod_identity_associations_arg=""
  local role_arn
  local trust_policy_json

  require_cmd aws
  require_cmd kubectl

  echo "Bootstrapping AWS EBS CSI driver addon..."
  addon_version="$(aws eks describe-addon-versions --addon-name "$addon_name" --kubernetes-version "$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.version' --output text)" --query 'addons[0].addonVersions[0].addonVersion' --output text)"

  if has_cluster_oidc_provider; then
    auth_mode="irsa"
    trust_policy_json="$(build_irsa_trust_policy_json)"
  else
    auth_mode="pod-identity"
    trust_policy_json="$(build_pod_identity_trust_policy_json)"
    bootstrap_pod_identity_agent
  fi

  ensure_aws_role_with_policy "$EBS_CSI_ROLE_NAME" "$EBS_CSI_POLICY_ARN" "$trust_policy_json"
  role_arn="$(aws iam get-role --role-name "$EBS_CSI_ROLE_NAME" --query 'Role.Arn' --output text)"

  if [[ "$auth_mode" == "pod-identity" ]]; then
    pod_identity_associations_arg="serviceAccount=$EBS_CSI_CONTROLLER_SERVICE_ACCOUNT,roleArn=$role_arn"
  fi

  if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" >/dev/null 2>&1; then
    addon_status="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" --query 'addon.status' --output text)"
    current_role_arn="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" --query 'addon.serviceAccountRoleArn' --output text 2>/dev/null || true)"

    if [[ "$auth_mode" == "pod-identity" && -n "$current_role_arn" && "$current_role_arn" != "None" ]]; then
      echo "Addon '$addon_name' is configured for IRSA, but this cluster lacks the matching IAM OIDC provider; recreating it with EKS Pod Identity..."
      aws eks delete-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" >/dev/null
      wait_for_eks_addon_deleted "$addon_name"
    else
      case "$addon_status" in
        CREATING|UPDATING)
          echo "Addon '$addon_name' is currently $addon_status; waiting for it to become ACTIVE before reconciling..."
          wait_for_eks_addon_active "$addon_name"
          ;;
        DELETING)
          echo "ERROR: addon '$addon_name' is currently DELETING; wait for deletion to finish before rerunning bootstrap." >&2
          exit 1
          ;;
      esac

      current_version="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" --query 'addon.addonVersion' --output text)"
      current_role_arn="$(aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$addon_name" --query 'addon.serviceAccountRoleArn' --output text 2>/dev/null || true)"

      if [[ "$auth_mode" == "irsa" && "$current_version" == "$addon_version" && "$current_role_arn" == "$role_arn" ]]; then
        echo "AWS EBS CSI driver addon is already configured with version $addon_version and IRSA role $role_arn."
        return 0
      fi

      if [[ "$auth_mode" == "pod-identity" && "$current_version" == "$addon_version" && ( -z "$current_role_arn" || "$current_role_arn" == "None" ) ]]; then
        echo "AWS EBS CSI driver addon is already configured with version $addon_version and EKS Pod Identity."
        return 0
      fi

      if [[ "$auth_mode" == "pod-identity" ]]; then
        aws eks update-addon \
          --cluster-name "$CLUSTER_NAME" \
          --addon-name "$addon_name" \
          --addon-version "$addon_version" \
          --pod-identity-associations "$pod_identity_associations_arg" \
          --resolve-conflicts OVERWRITE >/dev/null
      else
        aws eks update-addon \
          --cluster-name "$CLUSTER_NAME" \
          --addon-name "$addon_name" \
          --addon-version "$addon_version" \
          --service-account-role-arn "$role_arn" \
          --resolve-conflicts OVERWRITE >/dev/null
      fi
    fi
  else
    if [[ "$auth_mode" == "pod-identity" ]]; then
      aws eks create-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$addon_name" \
        --addon-version "$addon_version" \
        --pod-identity-associations "$pod_identity_associations_arg" \
        --resolve-conflicts OVERWRITE >/dev/null
    else
      aws eks create-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$addon_name" \
        --addon-version "$addon_version" \
        --service-account-role-arn "$role_arn" \
        --resolve-conflicts OVERWRITE >/dev/null
    fi
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
      postgresql)
        bootstrap_ebs_csi_driver
        bootstrap_flux_controllers
        bootstrap_kyverno
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
    postgresql)
      record_missing_crd "helmreleases.helm.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRelease CRD is missing), then rerun this command."
      record_missing_crd "helmrepositories.source.toolkit.fluxcd.io" \
        "Install Flux source/helm controllers first (HelmRepository CRD is missing), then rerun this command."
      record_missing_crd "clusterpolicies.kyverno.io" \
        "Install Kyverno first (ClusterPolicy CRD is missing), then rerun this command."
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
  # The Percona operator's namespace/watchNamespace must match this
  # environment's real MongoDB namespace (mongodb for dev, mongodb-uat for
  # uat -- see k8s/overlays/<env>/kustomization.yaml's own namespace
  # override) or the operator never reconciles the PerconaServerMongoDB CR
  # applied by apply_overlay. See #57.
  kubectl apply -k "$ROOT_DIR/gitops/operators/overlays/${ENVIRONMENT:-dev}"
}

apply_policies() {
  require_crd "clusterpolicies.kyverno.io" \
    "Install Kyverno first (ClusterPolicy CRD is missing), then rerun this command."
  kubectl apply -k "$ROOT_DIR/policies/kyverno"
}

apply_overlay() {
  kubectl apply -k "$ROOT_DIR/k8s/overlays/${ENVIRONMENT:-dev}"
}

SIGNOZ_CLICKHOUSE_READY_TIMEOUT_SECONDS="${SIGNOZ_CLICKHOUSE_READY_TIMEOUT_SECONDS:-300}"

# Pre-bumps the live ClickHouseInstallation CR's pod image to match the
# target SigNoz chart's own default clickhouse.image before the Helm
# upgrade runs. See issue #125: the chart's pre-upgrade migration hook
# (signoz-telemetrystore-migrator) runs a ClickHouse schema migration
# tied to the NEW chart version's expectations, but Helm applies chart
# values before the ClickHouse operator reconciles the CHI -- so on a
# ClickHouse major-version bump between chart versions, the hook can run
# against the still-old ClickHouse server and get stuck in
# `pending-upgrade` (observed with chart 0.130.1 -> 0.136.1, ClickHouse
# 25.5.6 -> 25.12.5, missing `object_serialization_version` support).
# Patching the CHI directly and waiting for the operator to roll the pod
# here closes that race for every future signoz apply, not just this one.
sync_clickhouse_image_ahead_of_helm_upgrade() {
  local namespace="$1"
  local chart_version="$2"
  local chi_name="signoz-clickhouse"

  if ! kubectl -n "$namespace" get chi "$chi_name" >/dev/null 2>&1; then
    # First-ever install: no live CHI yet for the operator to race against.
    return 0
  fi

  helm repo add signoz https://charts.signoz.io >/dev/null 2>&1 || true
  helm repo update signoz >/dev/null 2>&1 || true

  local target_image
  target_image="$(helm show values signoz/signoz --version "$chart_version" 2>/dev/null \
    | python3 -c '
import sys, yaml
values = yaml.safe_load(sys.stdin) or {}
image = (values.get("clickhouse") or {}).get("image") or {}
registry = image.get("registry", "docker.io")
repository = image.get("repository", "clickhouse/clickhouse-server")
tag = image.get("tag")
if tag:
    print(f"{registry}/{repository}:{tag}")
')"

  if [[ -z "$target_image" ]]; then
    echo "WARNING: could not resolve clickhouse.image from signoz chart ${chart_version}; skipping pre-upgrade ClickHouse image sync." >&2
    return 0
  fi

  local current_image
  current_image="$(kubectl -n "$namespace" get chi "$chi_name" \
    -o jsonpath='{.spec.templates.podTemplates[0].spec.containers[?(@.name=="clickhouse")].image}' 2>/dev/null || true)"

  if [[ "$current_image" == "$target_image" ]]; then
    return 0
  fi

  echo "Pre-bumping ClickHouse image ahead of SigNoz chart ${chart_version} upgrade: ${current_image:-<unknown>} -> ${target_image} (see issue #125)"
  kubectl -n "$namespace" patch chi "$chi_name" --type=json -p "$(python3 -c "
import json
print(json.dumps([{'op': 'replace', 'path': '/spec/templates/podTemplates/0/spec/containers/0/image', 'value': '${target_image}'}]))
")"

  echo "Waiting for ClickHouse pod to roll onto ${target_image} (timeout: ${SIGNOZ_CLICKHOUSE_READY_TIMEOUT_SECONDS}s) ..."
  local deadline=$((SECONDS + SIGNOZ_CLICKHOUSE_READY_TIMEOUT_SECONDS))
  while true; do
    local rolled_ready
    rolled_ready="$(kubectl -n "$namespace" get pods -l "clickhouse.altinity.com/chi=${chi_name}" \
      -o jsonpath='{range .items[*]}{.spec.containers[?(@.name=="clickhouse")].image}{" "}{.status.containerStatuses[?(@.name=="clickhouse")].ready}{"\n"}{end}' 2>/dev/null || true)"

    if [[ -n "$rolled_ready" ]] && ! grep -qv "^${target_image} true$" <<<"$rolled_ready"; then
      break
    fi

    if (( SECONDS >= deadline )); then
      echo "ERROR: ClickHouse pod(s) did not roll onto ${target_image} within ${SIGNOZ_CLICKHOUSE_READY_TIMEOUT_SECONDS}s." >&2
      echo "Hint: run 'kubectl -n $namespace get pods -l clickhouse.altinity.com/chi=${chi_name}' and 'kubectl -n $namespace get chi ${chi_name} -o yaml' for details." >&2
      exit 1
    fi
    sleep 5
  done
}

apply_signoz() {
  # Environment-aware namespace/overlay selection (see issue #118): every
  # other apply_* function in this file selects its overlay via
  # ${ENVIRONMENT:-dev} (see apply_overlay, apply_kustomize_operators) --
  # this one previously didn't, so it always applied gitops/signoz/base
  # (namespace 'signoz') regardless of --env, creating a stray duplicate
  # install in UAT/Production instead of targeting signoz-<env> per the
  # naming convention in CLAUDE.md. SIGNOZ_NAMESPACE is exported by
  # load_platform_env (config/environments/<env>.env) before this handler
  # runs; the ${SIGNOZ_NAMESPACE:-signoz} fallback only matters for the
  # legacy dev-only invocation path (scripts/legacy/dev/*), which does not
  # export it and has always meant the dev namespace 'signoz'.
  local signoz_namespace="${SIGNOZ_NAMESPACE:-signoz}"

  # SigNoz's PVCs (gitops/signoz/base/helmreleases.yaml) request the
  # gp3-mongodb StorageClass, which is otherwise only ever applied as part
  # of the mongodb/overlay scope's own manifests (k8s/base/
  # storageclass-gp3-mongodb.yaml) -- unrelated to SigNoz's own resource
  # ownership, but reusing the same StorageClass name. Without it, SigNoz's
  # PVCs stay Pending indefinitely ("unbound immediate
  # PersistentVolumeClaims") and this function's own readiness wait below
  # times out with no actionable error. Apply it here too (idempotent) so
  # this scope is self-sufficient regardless of whether mongodb has been
  # provisioned first -- same self-sufficiency pattern as the root-user
  # Secret handling immediately below.
  kubectl apply -f "$ROOT_DIR/k8s/base/storageclass-gp3-mongodb.yaml"

  # gitops/signoz/base/helmreleases.yaml wires SIGNOZ_USER_ROOT_EMAIL/PASSWORD
  # to the 'signoz-root-user' Secret via secretKeyRef (no `optional: true`),
  # so the signoz-0 pod hits CreateContainerConfigError if that Secret
  # doesn't exist yet. Ensure it exists BEFORE applying, so this scope is
  # self-sufficient regardless of call order.
  local secret_existed_before="false"
  if kubectl -n "$signoz_namespace" get secret signoz-root-user >/dev/null 2>&1; then
    secret_existed_before="true"
  fi
  "$ROOT_DIR/scripts/create-signoz-root-user-secret.sh" --namespace "$signoz_namespace"

  local signoz_chart_version
  signoz_chart_version="$(python3 -c '
import yaml
with open("'"$ROOT_DIR"'/gitops/signoz/base/helmreleases.yaml") as f:
    docs = [d for d in yaml.safe_load_all(f) if d and d.get("metadata", {}).get("name") == "signoz"]
print(docs[0]["spec"]["chart"]["spec"]["version"])
')"
  sync_clickhouse_image_ahead_of_helm_upgrade "$signoz_namespace" "$signoz_chart_version"

  kubectl apply -k "$ROOT_DIR/gitops/signoz/overlays/${ENVIRONMENT:-dev}"

  # If the Secret didn't exist before (this run just created it) AND the
  # signoz-0 pod already existed from a prior apply, it was created without
  # the env var resolving -- Kubernetes does not hot-inject secretKeyRef
  # values into a running/errored pod, so force a restart to pick it up.
  if [[ "$secret_existed_before" == "false" ]] && kubectl -n "$signoz_namespace" get statefulset signoz >/dev/null 2>&1; then
    echo "Restarting signoz StatefulSet so it picks up the newly created signoz-root-user Secret ..."
    kubectl -n "$signoz_namespace" rollout restart statefulset/signoz
  fi

  echo "Waiting for SigNoz application pod signoz-0 to become Ready (timeout: ${SIGNOZ_READY_TIMEOUT_SECONDS}s) ..."
  local deadline=$((SECONDS + SIGNOZ_READY_TIMEOUT_SECONDS))
  while true; do
    if kubectl -n "$signoz_namespace" get pod signoz-0 >/dev/null 2>&1; then
      local ready
      ready="$(kubectl -n "$signoz_namespace" get pod signoz-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
      if [[ "$ready" == "true" ]]; then
        break
      fi
    fi

    if (( SECONDS >= deadline )); then
      echo "ERROR: SigNoz application pod signoz-0 did not become Ready within ${SIGNOZ_READY_TIMEOUT_SECONDS}s." >&2
      echo "Hint: run 'kubectl -n $signoz_namespace get pods' and 'kubectl -n $signoz_namespace describe pod signoz-0' for details." >&2
      exit 1
    fi
    sleep 5
  done
}

apply_postgresql_operator() {
  require_crd "helmreleases.helm.toolkit.fluxcd.io" \
    "Install Flux source/helm controllers first (HelmRelease CRD is missing), then rerun this command."
  require_crd "helmrepositories.source.toolkit.fluxcd.io" \
    "Install Flux source/helm controllers first (HelmRepository CRD is missing), then rerun this command."
  kubectl apply -k "$ROOT_DIR/gitops/postgresql/base"
}

apply_postgresql_overlay() {
  apply_postgresql_coredb_overlay
  apply_postgresql_branddb_overlay
}

apply_postgresql_coredb_overlay() {
  kubectl apply -k "$ROOT_DIR/gitops/postgresql-coredb/overlays/${ENVIRONMENT:-dev}"
}

apply_postgresql_branddb_overlay() {
  kubectl apply -k "$ROOT_DIR/gitops/postgresql-branddb/overlays/${ENVIRONMENT:-dev}"
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

wait_for_postgresql_crd() {
  local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

  echo "Waiting for PostgreSQL CRD $POSTGRESQL_CRD_NAME (timeout: ${WAIT_TIMEOUT_SECONDS}s)..."
  while ! kubectl get crd "$POSTGRESQL_CRD_NAME" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "ERROR: PostgreSQL CRD '$POSTGRESQL_CRD_NAME' not found within ${WAIT_TIMEOUT_SECONDS}s." >&2
      echo "Hint: ensure Flux and the CNPG operator HelmRelease are healthy before applying the overlay." >&2
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
  postgresql)
    preflight_scope "$SCOPE"
    apply_postgresql_operator
    apply_policies
    wait_for_postgresql_crd
    apply_postgresql_overlay
    ;;
  postgresql-coredb)
    preflight_scope "postgresql"
    apply_postgresql_operator
    apply_policies
    wait_for_postgresql_crd
    apply_postgresql_coredb_overlay
    ;;
  postgresql-branddb)
    preflight_scope "postgresql"
    apply_postgresql_operator
    apply_policies
    wait_for_postgresql_crd
    apply_postgresql_branddb_overlay
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
    echo "Error: unknown scope '$SCOPE'. Expected one of: mongodb, mongo, postgresql, postgresql-coredb, postgresql-branddb, signoz, operators, policies, overlay, all" >&2
    usage
    exit 1
    ;;
esac

echo "Completed Kubernetes scope: $SCOPE"
