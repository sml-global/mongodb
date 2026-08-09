#!/usr/bin/env bash
#
# Environment-aware MongoDB Kubernetes-workload teardown, used by
# mongodb_internal_destroy_mongodb (lifecycle-handlers.sh). Ports the same
# ordering and hardening as scripts/legacy/dev/destroy.sh's
# destroy_mongodb_k8s() (CRD-before-operator ordering from #63/#77,
# --timeout on CRD deletes from #94, AWS CLI error handling from #93) but
# parameterized on the target environment's namespace/cluster/region
# instead of the legacy script's hardcoded `mongodb` namespace and dev-only
# defaults.
#
# scripts/legacy/dev/destroy.sh itself is never modified -- it stays frozen
# as the current DEV production path per CLAUDE.md. This is a net-new,
# independently callable implementation for the environment-aware handler
# only.
#
# No shared/global state: every function takes its environment's values as
# explicit arguments (see issue #111 -- a shared "current environment"
# global would reintroduce the same class of cross-environment hazard #95
# found once already, through a different mechanism).
#
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

_mongodb_destroy_k8s_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# mongodb_internal_destroy_k8s <namespace> <cluster_name> <aws_region> <escrow_dir> <environment>
#
# All five arguments are required and explicit -- no fallback to any
# global/environment variable of the same name.
mongodb_internal_destroy_k8s() {
  local namespace="$1"
  local cluster_name="$2"
  local aws_region="$3"
  local escrow_dir="$4"
  local environment="$5"

  if [[ -z "$namespace" || -z "$cluster_name" || -z "$aws_region" || -z "$escrow_dir" || -z "$environment" ]]; then
    _mongodb_destroy_k8s_error "mongodb_internal_destroy_k8s requires namespace, cluster_name, aws_region, escrow_dir, and environment"
    return 1
  fi

  printf 'Removing MongoDB workload resources in namespace %s...\n' "$namespace"

  # Step 1: Delete CRD resources FIRST (while operator is still running to
  # process finalizers) -- prevents namespace from getting stuck in
  # Terminating state (#63/#77). --timeout so a stuck finalizer degrades to
  # a warning instead of hanging the whole destroy run (#94).
  printf '  - Deleting PerconaServerMongoDBBackup CRs (backup finalizers need operator running)...\n'
  kubectl -n "$namespace" delete perconaservermongodbbackup --all --ignore-not-found=true --wait=true --timeout=60s || \
    printf '  - Warning: PerconaServerMongoDBBackup deletion did not complete within timeout (finalizer may be stuck)\n' >&2

  printf '  - Deleting PerconaServerMongoDB CR (PSMDB finalizers need operator running)...\n'
  kubectl -n "$namespace" delete perconaservermongodb psmdb --ignore-not-found=true --wait=true --timeout=60s || \
    printf '  - Warning: PerconaServerMongoDB deletion did not complete within timeout (finalizer may be stuck)\n' >&2

  printf 'Note: PVCs used reclaimPolicy: Retain — underlying EBS volumes are preserved as Released PVs. See docs/references/recovery-procedures.md § Orphaned EBS Volume Recovery to reclaim them.\n'

  # Step 2: Delete operator AFTER CRD resources (now safe -- no finalizers
  # left to process).
  printf '  - Deleting Percona operator HelmRelease...\n'
  kubectl -n "$namespace" delete helmrelease percona-server-mongodb-operator --ignore-not-found=true || true

  # Step 3: Remove cert-manager resources.
  kubectl -n "$namespace" delete certificate mongodb-ca mongodb-app-client psmdb-ca-cert psmdb-ssl psmdb-ssl-internal --ignore-not-found=true || true
  kubectl -n "$namespace" delete issuer mongodb-selfsigned mongodb-ca-issuer psmdb-issuer psmdb-ca-issuer --ignore-not-found=true || true

  # Step 4: Delete Pod Identity associations (AWS resource, not managed by
  # kubectl). A failed list call is surfaced as a warning, not silently
  # treated as "zero associations found" (#93).
  printf '  - Cleaning up EKS Pod Identity associations for %s namespace...\n' "$namespace"
  if command -v aws >/dev/null 2>&1; then
    local associations
    if ! associations="$(aws eks list-pod-identity-associations \
      --cluster-name "$cluster_name" \
      --region "$aws_region" \
      --query "associations[?namespace=='${namespace}'].associationId" \
      --output text 2>&1)"; then
      printf '  - Warning: failed to list Pod Identity associations (may require manual cleanup): %s\n' "$associations" >&2
      associations=""
    fi

    if [[ -n "$associations" ]]; then
      printf '  - Found Pod Identity associations to delete: %s\n' "$associations"
      local assoc_id
      for assoc_id in $associations; do
        printf '    - Deleting Pod Identity association: %s\n' "$assoc_id"
        aws eks delete-pod-identity-association \
          --cluster-name "$cluster_name" \
          --association-id "$assoc_id" \
          --region "$aws_region" 2>/dev/null || {
          printf '    - Warning: failed to delete Pod Identity association %s (may already be deleted)\n' "$assoc_id" >&2
        }
      done
    else
      printf '  - No Pod Identity associations found for %s namespace\n' "$namespace"
    fi
  else
    _mongodb_destroy_k8s_error "aws CLI not found, skipping Pod Identity association cleanup"
    printf '    Manual cleanup may be required: aws eks list-pod-identity-associations --cluster-name %s\n' "$cluster_name" >&2
  fi

  # Step 5: Remove secrets and local escrow files. Escrow filenames carry
  # the environment suffix (.local-dev-*, .local-uat-*), matching the
  # existing convention confirmed in .gitignore -- never a hardcoded "dev"
  # literal.
  printf '  - Removing MongoDB secrets and local escrow files...\n'
  kubectl -n "$namespace" delete secret psmdb-encryption-key psmdb-secrets internal-psmdb-users oms-audit-writer --ignore-not-found=true || true
  rm -f "${escrow_dir}/.local-${environment}-encryption-key.txt" "${escrow_dir}/.local-${environment}-user-passwords.txt"
}
