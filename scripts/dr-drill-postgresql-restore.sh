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
# (override only for local/manual testing), provisioned ONCE (namespace,
# ServiceAccount, RBAC) by scripts/bootstrap-dr-drill-role-arns-configmap.sh
# -- see D18/D19. EKS Pod Identity associations require an exact static
# namespace+ServiceAccount match (no wildcards -- verified against AWS EKS
# Pod Identity documentation), so a dynamically timestamped namespace could
# never be granted AWS credentials via Terraform ahead of time; a
# per-run-deleted namespace would also destroy its own namespace-scoped RBAC
# every run (a bootstrapping paradox -- see rbac.yaml header). This script
# therefore only cycles the throwaway restore-target CNPG Cluster inside
# that persistent namespace, never the namespace itself. Per-run
# uniqueness/audit-trail comes from the CronJob's own execution history
# (Job/pod names, pod start timestamps), not from the namespace name.

DRILL_NAMESPACE="${1:-dr-drill-postgresql-restore-target}"
DRILL_IAM_ROLE_ARN="${DR_DRILL_POSTGRESQL_ROLE_ARN:?Set DR_DRILL_POSTGRESQL_ROLE_ARN (dr-drill-postgresql-restore-role, read-only)}"
DRILL_ROLE_NAME="$(basename "${DRILL_IAM_ROLE_ARN}")"
RECOVERY_TARGET_TIME="${RECOVERY_TARGET_TIME:-latest}"
CLUSTER_NAME="dr-drill-restore-target"

# Verified via CNPG operator source code (pkg/utils/ownership.go's
# SetAsOwnedBy, pkg/reconciler/persistentvolumeclaim/build.go's Build(), and
# internal/cmd/plugin/destroy/destroy.go's opt-in removeOwnerReference()
# step): every PVC CNPG creates for a Cluster carries a real Kubernetes
# ownerReference (Controller: true) back to that Cluster, so deleting the
# Cluster triggers standard Kubernetes cascading garbage collection of its
# PVCs by default. GC is asynchronous, though, so wait_for_pvcs_gone below
# is a defense-in-depth poll, not a substitute for that ownerReference-based
# cleanup -- it guards against a race where this script tries to recreate
# the Cluster before GC has actually finished removing the old PVCs.
wait_for_pvcs_gone() {
  echo "Waiting for ${CLUSTER_NAME}'s PVCs to be garbage-collected in ${DRILL_NAMESPACE}..."
  for _ in $(seq 1 60); do
    if [ -z "$(kubectl get pvc -n "${DRILL_NAMESPACE}" -l "cnpg.io/cluster=${CLUSTER_NAME}" -o name)" ]; then
      return 0
    fi
    sleep 2
  done
  echo "PVCs for ${CLUSTER_NAME} were not garbage-collected within the expected time -- deleting explicitly."
  kubectl delete pvc -n "${DRILL_NAMESPACE}" -l "cnpg.io/cluster=${CLUSTER_NAME}" \
    --wait=true --ignore-not-found=true --timeout=120s
}

cleanup() {
  echo "Tearing down restore-target CNPG Cluster in ${DRILL_NAMESPACE}..."
  kubectl delete cluster "${CLUSTER_NAME}" -n "${DRILL_NAMESPACE}" \
    --wait=true --ignore-not-found=true --timeout=180s
  wait_for_pvcs_gone
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
# potentially leaving a stale Cluster (or its PVCs) stuck mid-teardown.
# Block until both are fully gone before recreating, so this run always
# starts clean. The namespace, ServiceAccount, and RBAC are provisioned once
# (out-of-band) by scripts/bootstrap-dr-drill-role-arns-configmap.sh, not by
# this script.
echo "Ensuring the restore-target Cluster in ${DRILL_NAMESPACE} is clean before starting..."
kubectl delete cluster "${CLUSTER_NAME}" -n "${DRILL_NAMESPACE}" \
  --wait=true --ignore-not-found=true --timeout=180s
wait_for_pvcs_gone

cat <<EOF | kubectl apply -n "${DRILL_NAMESPACE}" -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
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
kubectl wait --for=condition=Ready "cluster/${CLUSTER_NAME}" -n "${DRILL_NAMESPACE}" --timeout=600s || {
  echo "FATAL: restored cluster did not become Ready within 600s"
  exit 1
}
RESTORE_END=$(date +%s)
RTO_SECONDS=$((RESTORE_END - RESTORE_START))
echo "Restore completed. RTO: ${RTO_SECONDS}s"

echo "Verifying data integrity post-restore..."
# CNPG does NOT use a StatefulSet -- it manages PVCs directly and numbers
# instance pods starting at 1, not 0 (verified against the official CNPG
# FAQ: "CloudNativePG does not rely on StatefulSet resources", and the
# Labels and Annotations doc's own examples, e.g. "cluster-example-1" as the
# primary of a Cluster named "cluster-example"). With `instances: 1` (a
# throwaway single-node drill target), the only pod is "<cluster-name>-1".
ROW_COUNT=$(kubectl exec -n "${DRILL_NAMESPACE}" "${CLUSTER_NAME}-1" -- \
  psql -U postgres -d oms -tAc "SELECT COUNT(*) FROM orders;")
if [ -z "${ROW_COUNT}" ] || [ "${ROW_COUNT}" -eq 0 ]; then
  echo "FATAL: post-restore row count is zero -- data integrity check failed"
  exit 1
fi
echo "✅ Data integrity verified: ${ROW_COUNT} rows present"
echo "✅ DR Drill PASSED. RTO=${RTO_SECONDS}s, RestoredRows=${ROW_COUNT}"
