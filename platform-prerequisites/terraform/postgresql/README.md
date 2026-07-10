# Terraform PostgreSQL Root

## Purpose
This directory is the PostgreSQL-only runnable Terraform root.

Use it when you need Aurora PostgreSQL changes without touching MongoDB prerequisite resources.

## Read This First

| Question | Answer |
|---|---|
| What does this root provision? | Aurora PostgreSQL subnet group, security group/rules, cluster, and writer instance. |
| Which script uses this root? | `bash scripts/provision-platform-prereq.sh pg`. |
| Which default state key is used? | `oms/dev/pg.tfstate`. |
| Where is the canonical runbook? | `platform-prerequisites/terraform/README.md`. |
| New to a term here (root, state key, tfvars)? | [Glossary](../../../docs/references/glossary.md#terraform-basics). |

## Standard Use

1. Copy local vars file:

```bash
cp platform-prerequisites/terraform/postgresql/terraform.tfvars.sample platform-prerequisites/terraform/postgresql/terraform.tfvars
```

2. Fill required values (`vpc_id`, `private_subnet_ids`, `db_master_password`).
3. Run from repository root:

```bash
bash scripts/provision-platform-prereq.sh pg
```

## Boundaries
- Do not reuse this root's state key for the MongoDB root.
- Do not commit `terraform.tfvars`.

## Post-Apply Validation (PostgreSQL Scope)

After Terraform apply succeeds, verify the Aurora cluster is healthy:

1. **Check cluster status:**
```bash
aws rds describe-db-clusters \
  --db-cluster-identifier pg18-dev \
  --query 'DBClusters[0].Status' \
  --output text
# Expect: available
```

2. **Check writer instance:**
```bash
aws rds describe-db-instances \
  --db-instance-identifier pg18-dev-writer \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text
# Expect: available
```

3. **Get endpoint:**
```bash
aws rds describe-db-clusters \
  --db-cluster-identifier pg18-dev \
  --query 'DBClusters[0].Endpoint' \
  --output text
```

4. **Or use the unified verification:**
```bash
scripts/verify-platform-health.sh
```

Full step-by-step: [Operator Runbook](../../../docs/guides/operator-runbook.md)

## Related Documentation

| Topic | Link |
|---|---|
| Full operator runbook | [docs/guides/operator-runbook.md](../../../docs/guides/operator-runbook.md) |
| Architecture reference | [docs/guides/architect-reference.md](../../../docs/guides/architect-reference.md) |
| Verification commands | [docs/references/verification-commands.md](../../../docs/references/verification-commands.md) |
| Configuration catalog | [docs/operations/dev-configuration-catalog.md](../../../docs/operations/dev-configuration-catalog.md) |
