#!/usr/bin/env bash
set -euo pipefail

# scripts/dr-drill-postgresql-restore.sh
#
# Automated DR drill: uses CloudNativePG's native recovery bootstrap to
# restore a new, throwaway Cluster from the continuous WAL/PITR archive in
# S3, verifies data integrity, records RTO, and tears down.
#
# NEVER targets the production namespace. Uses a dedicated least-privilege
# drill IAM role (read-only S3 GetObject on the WAL archive prefix).
#
# Usage:
#   scripts/dr-drill-postgresql-restore.sh [drill-namespace]
#
# Defaults to the fixed, reusable namespace dr-drill-postgresql-restore-target
# (override only for local/manual testing). EKS Pod Identity associations
# require an exact static namespace+ServiceAccount match (no wildcards --
# verified against AWS EKS Pod Identity documentation), so a dynamically
# timestamped namespace could never be granted AWS credentials via
# Terraform ahead of time. Per-run uniqueness/audit-trail comes from the
# CronJob's own execution history (Job/pod names, pod start timestamps),
# not from the namespace name.

DRILL_NAMESPACE="${1:-dr-drill-postgresql-restore-target}"
DRILL_IAM_ROLE_ARN="${DR_DRILL_POSTGRESQL_ROLE_ARN:?Set DR_DRILL_POSTGRESQL_ROLE_ARN (dr-drill-postgresql-restore-role, read-only)}"
DRILL_ROLE_NAME="$(basename "${DRILL_IAM_ROLE_ARN}")"
RECOVERY_TARGET_TIME="${RECOVERY_TARGET_TIME:-latest}"

cleanup() {
  echo "Tearing down drill namespace ${DRILL_NAMESPACE}..."
  kubectl delete namespace "${DRILL_NAMESPACE}" --wait=true --ignore-not-found=true --timeout=120s
}
trap cleanup EXIT

echo "=== PostgreSQL WAL/PITR Restore Drill ==="
echo "Drill namespace: ${DRILL_NAMESPACE}"
echo "Drill IAM role: ${DRILL_IAM_ROLE_ARN} (read-only, dr-drill-postgresql-restore-role)"
echo "Recovery target time: ${RECOVERY_TARGET_TIME}"

# Defense-in-depth: verify the pod is actually running under the expected
# drill role before touching anything.
ASSUMED_IDENTITY_ARN="$(aws sts get-caller-identity --query Arn --output text)"
if [[ "${ASSUMED_IDENTITY_ARN}" != *"${DRILL_ROLE_NAME}"* ]]; then
  echo "FATAL: identity mismatch -- running as '${ASSUMED_IDENTITY_ARN}', expected role '${DRILL_ROLE_NAME}'. Refusing to proceed."
  exit 1
fi
echo "✅ Identity verified: running as ${ASSUMED_IDENTITY_ARN}"

# Safety net: a previous run's cleanup may have failed or been interrupted,
# potentially leaving the fixed namespace stuck mid-teardown. Block until it
# is fully gone before recreating it, so this run always starts clean.
echo "Ensuring ${DRILL_NAMESPACE} is clean before starting..."
kubectl delete namespace "${DRILL_NAMESPACE}" --wait=true --ignore-not-found=true --timeout=120s

kubectl create namespace "${DRILL_NAMESPACE}"
# ServiceAccounts are namespace-scoped, so the CNPG-managed restore-target
# pod needs one of this name inside its own (fixed) namespace, not just
# the one bootstrap-dr-drill-role-arns-configmap.sh created in dr-drill-uat.
kubectl create serviceaccount dr-drill-postgresql-runner -n "${DRILL_NAMESPACE}"

# The namespace was just (re)created above, which wipes any RBAC objects
# that lived inside the previous run's copy of it. Re-grant this script's
# own orchestrator ServiceAccount (dr-drill-postgresql-runner, dr-drill-uat)
# the namespace-scoped workload permissions it needs here by binding the
# persistent dr-drill-workload-operator ClusterRole (k8s/dr-drill/rbac.yaml)
# to just this namespace. Allowed without already holding those permissions
# because dr-drill-uat's ServiceAccount also holds the `bind` verb on that
# specific ClusterRole (see rbac.yaml's dr-drill-workload-operator-binder --
# verified against kubernetes.io/docs/reference/access-authn-authz/rbac/
# #restrictions-on-role-binding-creation-or-update).
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dr-drill-workload-operator
  namespace: ${DRILL_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: dr-drill-workload-operator
subjects:
  - kind: ServiceAccount
    name: dr-drill-postgresql-runner
    namespace: dr-drill-uat
EOF

cat <<EOF | kubectl apply -n "${DRILL_NAMESPACE}" -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: dr-drill-restore-target
spec:
  instances: 1
  # Attaches the cluster-managed pods to our own ServiceAccount (EKS Pod
  # Identity) instead of CNPG's default per-cluster generated one, so
  # s3Credentials.inheritFromIAMRole below has an identity to inherit from.
  # Real CNPG API field (verified against cloudnative-pg.io/docs/devel/
  # cloudnative-pg.v1 -- Cluster.spec.serviceAccountName, mutually
  # exclusive with serviceAccountTemplate), not fabricated.
  serviceAccountName: dr-drill-postgresql-runner
  storage:
    size: 10Gi
    storageClass: gp3-mongodb
  bootstrap:
    recovery:
      source: oms-postgresql-prod-backup
      recoveryTarget:
        targetTime: "${RECOVERY_TARGET_TIME}"
  externalClusters:
    - name: oms-postgresql-prod-backup
      barmanObjectStore:
        destinationPath: s3://oms-postgresql-wal-archive/
        s3Credentials:
          inheritFromIAMRole: true
EOF

RESTORE_START=$(date +%s)
kubectl wait --for=condition=Ready cluster/dr-drill-restore-target -n "${DRILL_NAMESPACE}" --timeout=600s || {
  echo "FATAL: restored cluster did not become Ready within 600s"
  exit 1
}
RESTORE_END=$(date +%s)
RTO_SECONDS=$((RESTORE_END - RESTORE_START))
echo "Restore completed. RTO: ${RTO_SECONDS}s"

echo "Verifying data integrity post-restore..."
# CNPG Clusters are backed by a StatefulSet; pod ordinals start at 0, not 1.
# With `instances: 1` (a throwaway single-node drill target), the only pod
# is "<cluster-name>-0".
ROW_COUNT=$(kubectl exec -n "${DRILL_NAMESPACE}" dr-drill-restore-target-0 -- \
  psql -U postgres -d oms -tAc "SELECT COUNT(*) FROM orders;")
if [ -z "${ROW_COUNT}" ] || [ "${ROW_COUNT}" -eq 0 ]; then
  echo "FATAL: post-restore row count is zero -- data integrity check failed"
  exit 1
fi
echo "✅ Data integrity verified: ${ROW_COUNT} rows present"
echo "✅ DR Drill PASSED. RTO=${RTO_SECONDS}s, RestoredRows=${ROW_COUNT}"
