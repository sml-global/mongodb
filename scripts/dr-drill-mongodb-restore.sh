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
#   scripts/dr-drill-mongodb-restore.sh [drill-namespace]
#
# Defaults to the fixed, reusable namespace dr-drill-mongodb-restore-target
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

DRILL_NAMESPACE="${1:-dr-drill-mongodb-restore-target}"
DRILL_IAM_ROLE_ARN="${DR_DRILL_MONGODB_ROLE_ARN:?Set DR_DRILL_MONGODB_ROLE_ARN (dr-drill-mongodb-restore-role, read-only)}"
DRILL_ROLE_NAME="$(basename "${DRILL_IAM_ROLE_ARN}")"

cleanup() {
  echo "Tearing down restore-target Deployment in ${DRILL_NAMESPACE}..."
  kubectl delete deployment mongodb-restore-target -n "${DRILL_NAMESPACE}" \
    --wait=true --ignore-not-found=true --timeout=120s
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

# Safety net: a previous run's cleanup may have failed or been interrupted,
# potentially leaving a stale Deployment stuck mid-teardown. Block until it
# is fully gone before recreating it, so this run always starts clean. The
# namespace, ServiceAccount, and RBAC are provisioned once (out-of-band) by
# scripts/bootstrap-dr-drill-role-arns-configmap.sh, not by this script.
echo "Ensuring the restore-target Deployment in ${DRILL_NAMESPACE} is clean before starting..."
kubectl delete deployment mongodb-restore-target -n "${DRILL_NAMESPACE}" \
  --wait=true --ignore-not-found=true --timeout=120s

echo "Deploying throwaway single-node MongoDB for restore target..."
kubectl apply -n "${DRILL_NAMESPACE}" -f "$(dirname "$0")/../k8s/dr-drill/mongodb-restore-target.yaml"
kubectl wait --for=condition=ready pod -l app=mongodb-restore-target -n "${DRILL_NAMESPACE}" --timeout=300s

# This script runs on the operator's machine / a CI runner, not inside the
# cluster -- so pbm and mongosh commands are always run via `kubectl exec`
# into the restore-target pod (matching the pattern already used by
# dr-drill-clickhouse-backup-restore.sh), never assumed reachable at
# localhost:27017 from the caller's machine.
#
# The restore-target pod has two containers (mongodb-restore-target.yaml):
# `mongodb` (has mongosh) and `pbm-agent` (has the pbm CLI). Every exec must
# target the correct one with `-c` -- `kubectl exec` silently defaults to the
# first container otherwise, which does not have the other tool installed.
RESTORE_POD=$(kubectl get pod -n "${DRILL_NAMESPACE}" -l app=mongodb-restore-target \
  -o jsonpath='{.items[0].metadata.name}')

echo "Configuring PBM storage backend (read-only drill role, oms-pbm-backups)..."
# No static access/secret keys: the pbm-agent container inherits AWS
# credentials from the pod's IRSA-annotated ServiceAccount (ambient AWS SDK
# credential chain), same as the identity guard above.
kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -c pbm-agent -- \
  pbm config --mongodb-uri="mongodb://localhost:27017" \
    --set storage.type=s3 \
    --set storage.s3.region="${AWS_REGION:-ap-east-1}" \
    --set storage.s3.bucket=oms-pbm-backups

echo "Checking PBM backup catalog (read-only drill role)..."
kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -c pbm-agent -- pbm status --mongodb-uri="mongodb://localhost:27017" || {
  echo "FATAL: pbm status failed -- cannot enumerate backups for drill"
  exit 1
}

LATEST_BACKUP=$(kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -c pbm-agent -- \
  pbm list --mongodb-uri="mongodb://localhost:27017" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' | tail -1)
if [ -z "${LATEST_BACKUP}" ]; then
  echo "FATAL: no backups found in PBM catalog"
  exit 1
fi
echo "Restoring backup: ${LATEST_BACKUP}"

RESTORE_START=$(date +%s)
kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -c pbm-agent -- \
  pbm restore "${LATEST_BACKUP}" --mongodb-uri="mongodb://localhost:27017" --wait
RESTORE_END=$(date +%s)
RTO_SECONDS=$((RESTORE_END - RESTORE_START))
echo "Restore completed. RTO: ${RTO_SECONDS}s"

echo "Verifying data integrity post-restore..."
DOC_COUNT=$(kubectl exec -n "${DRILL_NAMESPACE}" "${RESTORE_POD}" -c mongodb -- \
  mongosh "mongodb://localhost:27017" --quiet --eval "db.getSiblingDB('oms').orders.countDocuments({})")
if [ -z "${DOC_COUNT}" ] || [ "${DOC_COUNT}" -eq 0 ]; then
  echo "FATAL: post-restore document count is zero -- data integrity check failed"
  exit 1
fi
echo "✅ Data integrity verified: ${DOC_COUNT} documents present"
echo "✅ DR Drill PASSED. RTO=${RTO_SECONDS}s, RestoredDocs=${DOC_COUNT}"
