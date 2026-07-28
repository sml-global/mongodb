#!/usr/bin/env bash
set -euo pipefail

# scripts/bootstrap-dr-drill-role-arns-configmap.sh
#
# Reads the dr-drill IAM role ARNs from Terraform outputs
# (platform-prerequisites/terraform/dr-drill) and:
#   1. Creates/annotates the THREE dedicated ServiceAccounts
#      (dr-drill-mongodb-runner, dr-drill-postgresql-runner,
#      dr-drill-clickhouse-runner) with their IRSA role-arn annotation --
#      this is what actually binds each CronJob's pod to its own
#      least-privilege role (a ServiceAccount carries exactly one IRSA
#      role annotation, which is why there are three CronJobs/SAs, not one
#      running all three scripts -- see k8s/dr-drill/cronjob.yaml header).
#   2. Creates/updates the 'dr-drill-role-arns' ConfigMap the CronJobs read
#      via envFrom, used only for each script's defense-in-depth identity
#      *check* (D7) -- the actual privilege grant comes from #1.
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

MONGODB_ARN=$(terraform -chdir="$TF_DIR" output -raw dr_drill_mongodb_role_arn)
POSTGRESQL_ARN=$(terraform -chdir="$TF_DIR" output -raw dr_drill_postgresql_role_arn)
CLICKHOUSE_ARN=$(terraform -chdir="$TF_DIR" output -raw dr_drill_clickhouse_role_arn)

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating/annotating dedicated ServiceAccounts (one IRSA role each)..."
for pair in "dr-drill-mongodb-runner:${MONGODB_ARN}" "dr-drill-postgresql-runner:${POSTGRESQL_ARN}" "dr-drill-clickhouse-runner:${CLICKHOUSE_ARN}"; do
  sa_name="${pair%%:*}"
  role_arn="${pair#*:}"
  kubectl create serviceaccount "${sa_name}" --namespace "$NAMESPACE" --dry-run=client -o yaml \
    | kubectl annotate --local -f - "eks.amazonaws.com/role-arn=${role_arn}" -o yaml \
    | kubectl apply -f -
done

kubectl create configmap dr-drill-role-arns \
  --namespace "$NAMESPACE" \
  --from-literal=DR_DRILL_MONGODB_ROLE_ARN="$MONGODB_ARN" \
  --from-literal=DR_DRILL_POSTGRESQL_ROLE_ARN="$POSTGRESQL_ARN" \
  --from-literal=DR_DRILL_CLICKHOUSE_ROLE_ARN="$CLICKHOUSE_ARN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ 3 ServiceAccounts (IRSA-annotated) and dr-drill-role-arns ConfigMap up to date in namespace $NAMESPACE"
