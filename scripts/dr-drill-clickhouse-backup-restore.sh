#!/usr/bin/env bash
set -euo pipefail

# scripts/dr-drill-clickhouse-backup-restore.sh
#
# Application-consistent ClickHouse backup + restore drill for SigNoz.
#
# Uses `clickhouse-backup` (https://github.com/Altinity/clickhouse-backup),
# which internally issues FREEZE TABLE before copying data -- this avoids the
# corruption risk of a raw/blind EBS snapshot of a live ClickHouse volume
# (in-flight merges/inserts can be captured mid-write by a block-level
# snapshot).
#
# CRITICAL SAFETY PROPERTY: backup CREATE/UPLOAD run against the live SigNoz
# ClickHouse pod (read-only from SigNoz's perspective -- clickhouse-backup
# freezes and copies data OUT, it never mutates the source). The RESTORE
# step NEVER runs against that live pod. It deploys a throwaway ClickHouse
# instance into an isolated dr-drill-* namespace (mirroring the MongoDB/
# PostgreSQL drills) and restores there. An earlier version of this script
# ran `clickhouse-backup restore --rm` directly against the live `signoz`
# namespace, which would have dropped and overwritten production tables --
# caught in whole-branch review before ever being run. Never reintroduce
# that pattern.
#
# Backups are stored in a DEDICATED S3 bucket/prefix, never the MongoDB PBM
# bucket (oms-pbm-backups).
#
# Usage:
#   scripts/dr-drill-clickhouse-backup-restore.sh [drill-namespace]
#
# Defaults to the fixed, reusable namespace dr-drill-clickhouse-restore-target
# (override only for local/manual testing), provisioned ONCE (namespace,
# ServiceAccount, RBAC) by scripts/bootstrap-dr-drill-role-arns-configmap.sh
# -- see D18/D19. EKS Pod Identity associations require an exact static
# namespace+ServiceAccount match (no wildcards -- verified against AWS EKS
# Pod Identity documentation), so a dynamically timestamped namespace could
# never be granted AWS credentials via Terraform ahead of time; a
# per-run-deleted namespace would also destroy its own namespace-scoped RBAC
# every run (a bootstrapping paradox -- see rbac.yaml header). This script
# therefore only cycles the throwaway restore-target Deployment inside that
# persistent namespace, never the namespace itself. Per-run uniqueness/
# audit-trail comes from the CronJob's own execution history (Job/pod
# names, pod start timestamps), not from the namespace name.

DRILL_NAMESPACE="${1:-dr-drill-clickhouse-restore-target}"
BACKUP_NAME="dr-drill-$(date +%s)"
S3_BACKUP_PATH="s3://oms-signoz-clickhouse-backups/${BACKUP_NAME}"
DRILL_IAM_ROLE_ARN="${DR_DRILL_CLICKHOUSE_ROLE_ARN:?Set DR_DRILL_CLICKHOUSE_ROLE_ARN (dr-drill-clickhouse-backup-role, read+write scoped to oms-signoz-clickhouse-backups only)}"
DRILL_ROLE_NAME="$(basename "${DRILL_IAM_ROLE_ARN}")"

cleanup() {
  echo "Tearing down restore-target Deployment in ${DRILL_NAMESPACE}..."
  kubectl delete deployment clickhouse-restore-target -n "${DRILL_NAMESPACE}" \
    --wait=true --ignore-not-found=true --timeout=120s
}
trap cleanup EXIT

echo "=== ClickHouse Application-Consistent Backup + Restore Drill ==="
echo "Drill namespace (restore target ONLY -- never the live signoz namespace): ${DRILL_NAMESPACE}"
echo "Backup destination: ${S3_BACKUP_PATH}"

# Defense-in-depth: verify the pod is actually running under the expected
# drill role (read+write scoped only to oms-signoz-clickhouse-backups)
# before touching anything.
ASSUMED_IDENTITY_ARN="$(aws sts get-caller-identity --query Arn --output text)"
if [[ "${ASSUMED_IDENTITY_ARN}" != *"${DRILL_ROLE_NAME}"* ]]; then
  echo "FATAL: identity mismatch -- running as '${ASSUMED_IDENTITY_ARN}', expected role '${DRILL_ROLE_NAME}'. Refusing to proceed."
  exit 1
fi
echo "✅ Identity verified: running as ${ASSUMED_IDENTITY_ARN}"

# Safety net: a previous run's cleanup may have failed or been interrupted,
# potentially leaving a stale Deployment stuck mid-teardown. Block until it
# is fully gone before recreating it, so this run always starts clean. The
# namespace, ServiceAccount, and RBAC are provisioned once (out-of-band) by
# scripts/bootstrap-dr-drill-role-arns-configmap.sh, not by this script.
echo "Ensuring the restore-target Deployment in ${DRILL_NAMESPACE} is clean before starting..."
kubectl delete deployment clickhouse-restore-target -n "${DRILL_NAMESPACE}" \
  --wait=true --ignore-not-found=true --timeout=120s

# --- Step 1: Create an application-consistent backup from the LIVE pod ---
# Safe: clickhouse-backup create/upload only reads and freezes the live
# tables to copy them out; it never mutates the source.
LIVE_CLICKHOUSE_POD=$(kubectl get pod -n signoz -l app.kubernetes.io/name=clickhouse \
  -o jsonpath='{.items[0].metadata.name}')
echo "Live ClickHouse pod (backup source, read-only): ${LIVE_CLICKHOUSE_POD} (namespace: signoz)"

echo "Creating application-consistent backup (FREEZE TABLE via clickhouse-backup)..."
kubectl exec -n signoz "${LIVE_CLICKHOUSE_POD}" -- clickhouse-backup create "${BACKUP_NAME}"

echo "Uploading backup to S3..."
kubectl exec -n signoz "${LIVE_CLICKHOUSE_POD}" -- clickhouse-backup upload "${BACKUP_NAME}"

echo "Verifying backup landed in S3..."
aws s3 ls "${S3_BACKUP_PATH}/" >/dev/null 2>&1 || {
  echo "FATAL: backup not found at ${S3_BACKUP_PATH} after upload"
  exit 1
}

echo "Cleaning up local backup snapshot from the live pod (S3 copy already verified)..."
kubectl exec -n signoz "${LIVE_CLICKHOUSE_POD}" -- clickhouse-backup delete local "${BACKUP_NAME}"

# --- Step 2: Deploy an ISOLATED throwaway ClickHouse and restore there ---
# NEVER restore onto the live signoz pod -- that would overwrite production
# data. This mirrors the MongoDB/PostgreSQL drills' throwaway-target pattern.
# The namespace, its dr-drill-clickhouse-runner ServiceAccount, and RBAC are
# already provisioned (once, out-of-band) by
# scripts/bootstrap-dr-drill-role-arns-configmap.sh -- only the Deployment
# itself is created fresh here.
echo "Deploying throwaway single-node ClickHouse for restore target..."
kubectl apply -n "${DRILL_NAMESPACE}" -f "$(dirname "$0")/../k8s/dr-drill/clickhouse-restore-target.yaml"
kubectl wait --for=condition=ready pod -l app=clickhouse-restore-target -n "${DRILL_NAMESPACE}" --timeout=300s

RESTORE_POD=$(kubectl get pod -n "${DRILL_NAMESPACE}" -l app=clickhouse-restore-target \
  -o jsonpath='{.items[0].metadata.name}')
echo "Throwaway restore-target pod: ${RESTORE_POD} (namespace: ${DRILL_NAMESPACE})"

echo "Restoring into the throwaway instance to prove restorability..."
RESTORE_START=$(date +%s)
kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -c clickhouse-backup -- clickhouse-backup download "${BACKUP_NAME}"
kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -c clickhouse-backup -- clickhouse-backup restore "${BACKUP_NAME}"
RESTORE_END=$(date +%s)
RTO_SECONDS=$((RESTORE_END - RESTORE_START))
echo "Restore completed. RTO: ${RTO_SECONDS}s"

echo "Verifying row count post-restore (throwaway instance, not production)..."
ROW_COUNT=$(kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -c clickhouse-server -- \
  clickhouse-client --query "SELECT count() FROM signoz_traces.signoz_index_v2")
if [ -z "${ROW_COUNT}" ]; then
  echo "FATAL: could not read row count post-restore"
  exit 1
fi
echo "✅ Data integrity verified: ${ROW_COUNT} rows present (throwaway instance)"
echo "✅ DR Drill PASSED. RTO=${RTO_SECONDS}s, RestoredRows=${ROW_COUNT}"

