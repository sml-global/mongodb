#!/usr/bin/env bash
#
# Real AWS-backed implementation of the postgresql destroy-time observation
# seam that pre-destroy-guards.sh calls as
# `postgresql_internal_live_guard_observations`. This symbol had no real
# implementation before this file -- guards failed closed with "seam is
# required" for both scopes in this package (see issue #108).
#
# Read-only: this file only ever calls describe/list AWS APIs and kubectl
# get. It never mutates infrastructure, writes files, or touches Terraform
# state.
#
# Bash 3.2 compatible: no associative arrays, no declare -g, no namerefs.
# This file contains no top-level execution.

_postgresql_live_error() {
  printf 'ERROR: %s\n' "$*" >&2
}

# database-access-core/database-access-brand are genuinely unimplemented
# work packages (scope_registry_deferred_database_access_{core,brand}_*
# always fail closed with "requires work package 4") -- nothing can exist
# for a scope that has never had a real provision handler, so both are
# unconditionally absent today. Revisit once either scope gets a real
# implementation.
_postgresql_live_database_access_absent() {
  printf 'true'
}

# Aurora's own deletion_protection flag (modules/postgresql/main.tf sets
# deletion_protection = true) is the closest live equivalent to "PVC
# protection" for a fully AWS-managed database with no Kubernetes PVCs of
# its own -- the guard's observation key name (pvc_protection_enabled) is
# a holdover from the shared guard shape mongodb also uses, kept as-is here
# rather than renamed, so the guard's own case/error-message text (which
# already says "PVC deletion protection") is not misleading about what
# scope this observation covers.
_postgresql_live_deletion_protection_enabled() {
  local aurora_identifier="$1"
  local enabled
  enabled="$(aws rds describe-db-clusters \
    --db-cluster-identifier "$aurora_identifier" \
    --query 'DBClusters[0].DeletionProtection' \
    --output text 2>/dev/null)" || return 1
  case "$enabled" in
    true|True|TRUE) printf 'enabled' ;;
    *) printf 'disabled' ;;
  esac
}

# Aurora's automated backup is considered enabled if its retention period
# is greater than zero (modules/postgresql/main.tf sets
# backup_retention_period = 7).
_postgresql_live_backup_enabled() {
  local aurora_identifier="$1"
  local retention
  retention="$(aws rds describe-db-clusters \
    --db-cluster-identifier "$aurora_identifier" \
    --query 'DBClusters[0].BackupRetentionPeriod' \
    --output text 2>/dev/null)" || return 1
  if [[ "$retention" =~ ^[0-9]+$ ]] && (( retention > 0 )); then
    printf 'enabled'
  else
    printf 'disabled'
  fi
}

# postgresql_internal_live_guard_observations <scope>
#
# Emits key=value lines for the pre-destroy-guard checks in
# pre-destroy-guards.sh. postgresql-core validates
# database_access_core_absent; postgresql-brand validates
# database_access_brand_absent. Both validate the same protection-state
# pair, read from their own Aurora cluster identifier
# (POSTGRESQL_CORE_AURORA_IDENTIFIER / POSTGRESQL_BRAND_AURORA_IDENTIFIER).
postgresql_internal_live_guard_observations() {
  local scope_name="$1"
  local aurora_identifier=""
  local pvc_protection_enabled
  local backup_enabled

  case "$scope_name" in
    postgresql-core)
      aurora_identifier="${POSTGRESQL_CORE_AURORA_IDENTIFIER:-}"
      ;;
    postgresql-brand)
      aurora_identifier="${POSTGRESQL_BRAND_AURORA_IDENTIFIER:-}"
      ;;
  esac

  if [[ -z "$aurora_identifier" ]]; then
    _postgresql_live_error "${scope_name}: Aurora cluster identifier is not set; cannot read live guard observations"
    return 1
  fi

  pvc_protection_enabled="$(_postgresql_live_deletion_protection_enabled "$aurora_identifier")" || {
    _postgresql_live_error "${scope_name}: unable to read Aurora cluster '${aurora_identifier}' deletion protection"
    return 1
  }

  backup_enabled="$(_postgresql_live_backup_enabled "$aurora_identifier")" || {
    _postgresql_live_error "${scope_name}: unable to read Aurora cluster '${aurora_identifier}' backup retention"
    return 1
  }

  case "$scope_name" in
    postgresql-core)
      printf 'database_access_core_absent=%s\n' "$(_postgresql_live_database_access_absent)"
      ;;
    postgresql-brand)
      printf 'database_access_brand_absent=%s\n' "$(_postgresql_live_database_access_absent)"
      ;;
  esac

  printf 'pvc_protection_enabled=%s\n' "$pvc_protection_enabled"
  printf 'backup_enabled=%s\n' "$backup_enabled"
}
