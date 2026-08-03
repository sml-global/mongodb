#!/usr/bin/env bash
#
# PostgreSQL verifier implementation.
#
# Source path (via foundation-validated package-source helper only):
#   source_package_internal_library "40-postgresql/internal/verifiers.sh"
#
# Exports only distinct verifier-side postgresql_internal_* symbols. Never
# defines lifecycle, handler, pre-destroy-guard, or canonical registry
# wrapper symbols. Bash 3.2 compatible: no associative arrays, no declare -g,
# no namerefs. This file contains no top-level execution.
#
# Dev/SIT verify the in-cluster CNPG Cluster CR; UAT/Prod verify the managed
# Aurora cluster via the AWS CLI (see docs/references/postgresql-platform-contract.md).

postgresql_internal_verifier_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

postgresql_internal_postgresql_core_verifier() {
  local namespace="${POSTGRESQL_NAMESPACE:-postgresql}"
  local cluster_name="${POSTGRESQL_CLUSTER_NAME:-oms-postgresql}"

  case "${ENVIRONMENT:-dev}" in
    dev|sit)
      if ! kubectl -n "$namespace" get cluster.postgresql.cnpg.io "$cluster_name" >/dev/null 2>&1; then
        postgresql_internal_verifier_error "CNPG Cluster '$cluster_name' not found in namespace '$namespace'"
        return 1
      fi

      local phase
      phase="$(kubectl -n "$namespace" get cluster.postgresql.cnpg.io "$cluster_name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      if [[ "$phase" != "Cluster in healthy state" ]]; then
        postgresql_internal_verifier_error "CNPG Cluster '$cluster_name' phase is '${phase:-unknown}', expected 'Cluster in healthy state'"
        return 1
      fi
      ;;
    *)
      local aurora_identifier="${POSTGRESQL_CORE_AURORA_IDENTIFIER:-}"
      if [[ -z "$aurora_identifier" ]]; then
        postgresql_internal_verifier_error "POSTGRESQL_CORE_AURORA_IDENTIFIER is not set; cannot verify Aurora cluster for ${ENVIRONMENT}"
        return 1
      fi
      local status
      status="$(aws rds describe-db-clusters --db-cluster-identifier "$aurora_identifier" --query 'DBClusters[0].Status' --output text 2>/dev/null || echo "NOT_FOUND")"
      if [[ "$status" != "available" ]]; then
        postgresql_internal_verifier_error "Aurora cluster '$aurora_identifier' status is '$status', expected 'available'"
        return 1
      fi
      ;;
  esac

  printf 'PASS: postgresql-core cluster verified: %s/%s\n' "$namespace" "$cluster_name"
}

postgresql_internal_postgresql_brand_verifier() {
  local aurora_identifier="${POSTGRESQL_BRAND_AURORA_IDENTIFIER:-}"

  if [[ -z "$aurora_identifier" ]]; then
    postgresql_internal_verifier_error "POSTGRESQL_BRAND_AURORA_IDENTIFIER is not set; cannot verify brand Aurora cluster"
    return 1
  fi

  local status
  status="$(aws rds describe-db-clusters --db-cluster-identifier "$aurora_identifier" --query 'DBClusters[0].Status' --output text 2>/dev/null || echo "NOT_FOUND")"
  if [[ "$status" != "available" ]]; then
    postgresql_internal_verifier_error "Aurora cluster '$aurora_identifier' status is '$status', expected 'available'"
    return 1
  fi

  printf 'PASS: postgresql-brand verified: %s\n' "$aurora_identifier"
}
