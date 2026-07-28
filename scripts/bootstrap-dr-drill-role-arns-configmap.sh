#!/usr/bin/env bash
set -euo pipefail

# scripts/bootstrap-dr-drill-role-arns-configmap.sh
#
# Reads the dr-drill IAM role ARNs from Terraform outputs
# (platform-prerequisites/terraform/dr-drill) and creates/updates the
# 'dr-drill-role-arns' ConfigMap the weekly CronJob (k8s/dr-drill/cronjob.yaml)
# reads via envFrom. Idempotent -- safe to re-run any time after
# `terraform apply`. Run this manually as part of the provisioning workflow;
# it has no GitOps/Flux ordering dependency because it is not reconciled by
# Flux at all.
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

kubectl create configmap dr-drill-role-arns \
  --namespace "$NAMESPACE" \
  --from-literal=DR_DRILL_MONGODB_ROLE_ARN="$MONGODB_ARN" \
  --from-literal=DR_DRILL_POSTGRESQL_ROLE_ARN="$POSTGRESQL_ARN" \
  --from-literal=DR_DRILL_CLICKHOUSE_ROLE_ARN="$CLICKHOUSE_ARN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ dr-drill-role-arns ConfigMap up to date in namespace $NAMESPACE"
