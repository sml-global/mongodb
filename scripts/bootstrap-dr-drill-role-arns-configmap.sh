#!/usr/bin/env bash
set -euo pipefail

# scripts/bootstrap-dr-drill-role-arns-configmap.sh
#
# Reads the dr-drill IAM role ARNs from Terraform outputs
# (platform-prerequisites/terraform/dr-drill) and:
#   1. Creates the THREE dedicated ServiceAccounts (dr-drill-mongodb-runner,
#      dr-drill-postgresql-runner, dr-drill-clickhouse-runner). No IRSA
#      role-arn annotation is needed -- these use EKS Pod Identity, which
#      binds a role to a namespace/ServiceAccount pair on the AWS side via
#      `aws_eks_pod_identity_association` (see
#      platform-prerequisites/terraform/dr-drill/main.tf); the ServiceAccount
#      object itself just needs to exist with the right name. There are
#      still three separate ServiceAccounts (not one) because Pod Identity,
#      like IRSA before it, binds exactly one role per ServiceAccount -- see
#      k8s/dr-drill/cronjob.yaml header.
#   2. Creates/updates the 'dr-drill-role-arns' ConfigMap the CronJobs read
#      via envFrom, used only for each script's defense-in-depth identity
#      *check* (D7) -- the actual privilege grant comes from the Pod
#      Identity association in Terraform.
#
# Idempotent -- safe to re-run any time after `terraform apply`. Run this
# manually as part of the provisioning workflow; it has no GitOps/Flux
# ordering dependency because none of this is reconciled by Flux.
#
# RBAC (namespace/pod/deployment/CNPG-cluster permissions for these
# ServiceAccounts) is applied separately via k8s/dr-drill/rbac.yaml.
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

echo "Creating dedicated ServiceAccounts (Pod Identity association, no annotation needed)..."
for sa_name in dr-drill-mongodb-runner dr-drill-postgresql-runner dr-drill-clickhouse-runner; do
  kubectl create serviceaccount "${sa_name}" --namespace "$NAMESPACE" --dry-run=client -o yaml \
    | kubectl apply -f -
done

kubectl create configmap dr-drill-role-arns \
  --namespace "$NAMESPACE" \
  --from-literal=DR_DRILL_MONGODB_ROLE_ARN="$MONGODB_ARN" \
  --from-literal=DR_DRILL_POSTGRESQL_ROLE_ARN="$POSTGRESQL_ARN" \
  --from-literal=DR_DRILL_CLICKHOUSE_ROLE_ARN="$CLICKHOUSE_ARN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ 3 ServiceAccounts (Pod Identity) and dr-drill-role-arns ConfigMap up to date in namespace $NAMESPACE"

