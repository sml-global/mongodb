#!/usr/bin/env bash
set -euo pipefail

# scripts/bootstrap-dr-drill-role-arns-configmap.sh
#
# Reads the dr-drill IAM role ARNs from Terraform outputs
# (platform-prerequisites/terraform/dr-drill) and:
#   1. Creates the dr-drill-uat orchestrator namespace, plus the 3 FIXED,
#      reusable restore-target namespaces (dr-drill-mongodb-restore-target,
#      dr-drill-postgresql-restore-target, dr-drill-clickhouse-restore-target
#      -- see D18/D19). These are provisioned ONCE, here, and never deleted
#      by the drill scripts themselves (only the workload object inside each
#      one -- a Deployment, or the CNPG Cluster for postgresql -- is deleted
#      and recreated on every drill run).
#   2. Creates the THREE dedicated ServiceAccounts (dr-drill-mongodb-runner,
#      dr-drill-postgresql-runner, dr-drill-clickhouse-runner) TWICE each:
#      once in dr-drill-uat (the orchestrator/CronJob pod's identity) and
#      once in that drill's own fixed restore-target namespace (the
#      restore-target pod's identity, matching each k8s/dr-drill/*.yaml's
#      serviceAccountName / the CNPG Cluster's spec.serviceAccountName). No
#      IRSA role-arn annotation is needed -- these use EKS Pod Identity,
#      which binds a role to a namespace/ServiceAccount pair on the AWS side
#      via `aws_eks_pod_identity_association` (see
#      platform-prerequisites/terraform/dr-drill/main.tf, which defines
#      associations for both namespace/ServiceAccount pairs per drill); the
#      ServiceAccount object itself just needs to exist with the right name.
#   3. Applies k8s/dr-drill/rbac.yaml, which grants the 3 orchestrator
#      ServiceAccounts (dr-drill-uat) namespace-scoped workload permissions
#      against their own fixed restore-target namespace via 3 static
#      RoleBindings. Applied here (after the restore-target namespaces
#      above are guaranteed to exist) rather than self-applied by the drill
#      scripts at runtime, so no runner ServiceAccount ever needs
#      `rolebindings:create`/`clusterroles:bind` permission (see rbac.yaml
#      header and D19 for why the prior self-applying design was an
#      over-broad privilege-escalation risk).
#   4. Creates/updates the 'dr-drill-role-arns' ConfigMap the CronJobs read
#      via envFrom, used only for each script's defense-in-depth identity
#      *check* (D7) -- the actual privilege grant comes from the Pod
#      Identity association in Terraform.
#
# Idempotent -- safe to re-run any time after `terraform apply`. Run this
# manually as part of the provisioning workflow; it has no GitOps/Flux
# ordering dependency because none of this is reconciled by Flux.
#
# Usage:
#   scripts/bootstrap-dr-drill-role-arns-configmap.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT_DIR/platform-prerequisites/terraform/dr-drill"
NAMESPACE="dr-drill-uat"
RESTORE_TARGET_NAMESPACES=(
  "dr-drill-mongodb-restore-target:dr-drill-mongodb-runner"
  "dr-drill-postgresql-restore-target:dr-drill-postgresql-runner"
  "dr-drill-clickhouse-restore-target:dr-drill-clickhouse-runner"
)

MONGODB_ARN=$(terraform -chdir="$TF_DIR" output -raw dr_drill_mongodb_role_arn)
POSTGRESQL_ARN=$(terraform -chdir="$TF_DIR" output -raw dr_drill_postgresql_role_arn)
CLICKHOUSE_ARN=$(terraform -chdir="$TF_DIR" output -raw dr_drill_clickhouse_role_arn)

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating the 3 fixed, reusable restore-target namespaces..."
for entry in "${RESTORE_TARGET_NAMESPACES[@]:-}"; do
  restore_namespace="${entry%%:*}"
  kubectl create namespace "${restore_namespace}" --dry-run=client -o yaml | kubectl apply -f -
done

echo "Creating dedicated ServiceAccounts (Pod Identity association, no annotation needed)..."
for sa_name in dr-drill-mongodb-runner dr-drill-postgresql-runner dr-drill-clickhouse-runner; do
  kubectl create serviceaccount "${sa_name}" --namespace "$NAMESPACE" --dry-run=client -o yaml \
    | kubectl apply -f -
done

echo "Creating matching ServiceAccounts inside each fixed restore-target namespace..."
for entry in "${RESTORE_TARGET_NAMESPACES[@]:-}"; do
  restore_namespace="${entry%%:*}"
  restore_sa="${entry##*:}"
  kubectl create serviceaccount "${restore_sa}" --namespace "${restore_namespace}" --dry-run=client -o yaml \
    | kubectl apply -f -
done

echo "Applying dr-drill RBAC (k8s/dr-drill/rbac.yaml)..."
kubectl apply -f "$ROOT_DIR/k8s/dr-drill/rbac.yaml"

kubectl create configmap dr-drill-role-arns \
  --namespace "$NAMESPACE" \
  --from-literal=DR_DRILL_MONGODB_ROLE_ARN="$MONGODB_ARN" \
  --from-literal=DR_DRILL_POSTGRESQL_ROLE_ARN="$POSTGRESQL_ARN" \
  --from-literal=DR_DRILL_CLICKHOUSE_ROLE_ARN="$CLICKHOUSE_ARN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Namespaces, ServiceAccounts (Pod Identity), RBAC, and dr-drill-role-arns ConfigMap up to date"

