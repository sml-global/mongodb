#!/usr/bin/env bash
set -euo pipefail

# scripts/dr-drill-mongodb-restore.sh
#
# Automated DR drill: restores the most recent PBM (Percona Backup for
# MongoDB) backup from S3 into an isolated, throwaway namespace in the UAT
# cluster, verifies data integrity, records RTO, and tears down.
#
# NEVER targets the production namespace. Uses a dedicated least-privilege
# drill IAM role (read-only S3 GetObject on the backup prefix) -- never the
# production PBM write role.
#
# Usage:
#   scripts/dr-drill-mongodb-restore.sh [--namespace <drill-ns>]

DRILL_NAMESPACE="${1:-dr-drill-mongodb-$(date +%s)}"
DRILL_IAM_ROLE_ARN="${DR_DRILL_MONGODB_ROLE_ARN:?Set DR_DRILL_MONGODB_ROLE_ARN (dr-drill-mongodb-restore-role, read-only)}"
DRILL_ROLE_NAME="$(basename "${DRILL_IAM_ROLE_ARN}")"

cleanup() {
  echo "Tearing down drill namespace ${DRILL_NAMESPACE}..."
  kubectl delete namespace "${DRILL_NAMESPACE}" --ignore-not-found --wait=false
}
trap cleanup EXIT

echo "=== MongoDB PBM Restore Drill ==="
echo "Drill namespace: ${DRILL_NAMESPACE}"
echo "Drill IAM role: ${DRILL_IAM_ROLE_ARN} (read-only, dr-drill-mongodb-restore-role)"

# Defense-in-depth: verify the pod is actually running under the expected
# drill role before touching anything. Guards against a misconfigured IRSA
# ServiceAccount binding accidentally granting production credentials.
ASSUMED_IDENTITY_ARN="$(aws sts get-caller-identity --query Arn --output text)"
if [[ "${ASSUMED_IDENTITY_ARN}" != *"${DRILL_ROLE_NAME}"* ]]; then
  echo "FATAL: identity mismatch -- running as '${ASSUMED_IDENTITY_ARN}', expected role '${DRILL_ROLE_NAME}'. Refusing to proceed."
  exit 1
fi
echo "✅ Identity verified: running as ${ASSUMED_IDENTITY_ARN}"

kubectl create namespace "${DRILL_NAMESPACE}"

echo "Deploying throwaway single-node MongoDB for restore target..."
kubectl apply -n "${DRILL_NAMESPACE}" -f "$(dirname "$0")/../k8s/dr-drill/mongodb-restore-target.yaml"
kubectl wait --for=condition=ready pod -l app=mongodb-restore-target -n "${DRILL_NAMESPACE}" --timeout=300s

# This script runs on the operator's machine / a CI runner, not inside the
# cluster -- so pbm and mongosh commands are always run via `kubectl exec`
# into the restore-target pod (matching the pattern already used by
# dr-drill-clickhouse-backup-restore.sh), never assumed reachable at
# localhost:27017 from the caller's machine.
RESTORE_POD=$(kubectl get pod -n "${DRILL_NAMESPACE}" -l app=mongodb-restore-target \
  -o jsonpath='{.items[0].metadata.name}')

echo "Checking PBM backup catalog (read-only drill role)..."
kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -- pbm status --mongodb-uri="mongodb://localhost:27017" || {
  echo "FATAL: pbm status failed -- cannot enumerate backups for drill"
  exit 1
}

LATEST_BACKUP=$(kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -- \
  pbm list --mongodb-uri="mongodb://localhost:27017" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' | tail -1)
if [ -z "${LATEST_BACKUP}" ]; then
  echo "FATAL: no backups found in PBM catalog"
  exit 1
fi
echo "Restoring backup: ${LATEST_BACKUP}"

RESTORE_START=$(date +%s)
kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -- \
  pbm restore "${LATEST_BACKUP}" --mongodb-uri="mongodb://localhost:27017" --wait
RESTORE_END=$(date +%s)
RTO_SECONDS=$((RESTORE_END - RESTORE_START))
echo "Restore completed. RTO: ${RTO_SECONDS}s"

echo "Verifying data integrity post-restore..."
DOC_COUNT=$(kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -- \
  mongosh "mongodb://localhost:27017" --quiet --eval "db.getSiblingDB('oms').orders.countDocuments({})")
if [ -z "${DOC_COUNT}" ] || [ "${DOC_COUNT}" -eq 0 ]; then
  echo "FATAL: post-restore document count is zero -- data integrity check failed"
  exit 1
fi
echo "✅ Data integrity verified: ${DOC_COUNT} documents present"
echo "✅ DR Drill PASSED. RTO=${RTO_SECONDS}s, RestoredDocs=${DOC_COUNT}"
