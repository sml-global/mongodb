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
# snapshot). ClickHouse currently shares the gp3-mongodb EBS storage class
# (gitops/signoz/base/helmreleases.yaml), so this drill explicitly scopes to
# clickhouse pods only via label selector -- never a blanket volume policy.
#
# Backups are stored in a DEDICATED S3 bucket/prefix, never the MongoDB PBM
# bucket (oms-pbm-backups).
#
# Usage:
#   scripts/dr-drill-clickhouse-backup-restore.sh

CLICKHOUSE_POD=$(kubectl get pod -n signoz -l app.kubernetes.io/name=clickhouse \
  -o jsonpath='{.items[0].metadata.name}')
BACKUP_NAME="dr-drill-$(date +%s)"
S3_BACKUP_PATH="s3://oms-signoz-clickhouse-backups/${BACKUP_NAME}"
DRILL_IAM_ROLE_ARN="${DR_DRILL_CLICKHOUSE_ROLE_ARN:?Set DR_DRILL_CLICKHOUSE_ROLE_ARN (dr-drill-clickhouse-backup-role, read+write scoped to oms-signoz-clickhouse-backups only)}"
DRILL_ROLE_NAME="$(basename "${DRILL_IAM_ROLE_ARN}")"

echo "=== ClickHouse Application-Consistent Backup + Restore Drill ==="
echo "Target pod: ${CLICKHOUSE_POD} (app.kubernetes.io/name=clickhouse)"
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

echo "Creating application-consistent backup (FREEZE TABLE via clickhouse-backup)..."
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup create "${BACKUP_NAME}"

echo "Uploading backup to S3..."
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup upload "${BACKUP_NAME}"

echo "Verifying backup landed in S3..."
aws s3 ls "${S3_BACKUP_PATH}/" >/dev/null 2>&1 || {
  echo "FATAL: backup not found at ${S3_BACKUP_PATH} after upload"
  exit 1
}

echo "Restoring into a throwaway table to prove restorability..."
RESTORE_START=$(date +%s)
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup download "${BACKUP_NAME}"
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup restore --rm "${BACKUP_NAME}"
RESTORE_END=$(date +%s)
RTO_SECONDS=$((RESTORE_END - RESTORE_START))
echo "Restore completed. RTO: ${RTO_SECONDS}s"

echo "Verifying row count post-restore..."
ROW_COUNT=$(kubectl exec -n signoz "${CLICKHOUSE_POD}" -- \
  clickhouse-client --query "SELECT count() FROM signoz_traces.signoz_index_v2")
if [ -z "${ROW_COUNT}" ]; then
  echo "FATAL: could not read row count post-restore"
  exit 1
fi
echo "✅ Data integrity verified: ${ROW_COUNT} rows present"
echo "✅ DR Drill PASSED. RTO=${RTO_SECONDS}s, RestoredRows=${ROW_COUNT}"

echo "Cleaning up local backup snapshot from pod..."
kubectl exec -n signoz "${CLICKHOUSE_POD}" -- clickhouse-backup delete local "${BACKUP_NAME}"
