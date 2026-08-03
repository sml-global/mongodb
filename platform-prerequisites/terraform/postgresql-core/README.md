# Terraform PostgreSQL "Core" Root

## Purpose
This directory is the PostgreSQL "core" database Terraform root — the
primary application Aurora database. It has an independent sibling,
`postgresql-brand` (see docs/guides/enterprise-architecture.md § Production
Readiness Assessment — Now — "Aurora brand database"), which invokes the
same shared `../modules/postgresql` module with its own name/instance count
so a brand outage/misconfiguration/destroy cannot affect core.

Use it when you need Aurora PostgreSQL changes without touching MongoDB
prerequisite resources.

## Read This First

| Question | Answer |
|---|---|
| What does this root provision? | The CNPG backup S3 IAM policy attachment, plus (via the shared `modules/postgresql` module) Aurora PostgreSQL subnet group, security group/rules, cluster, and writer instance(s). |
| Which script uses this root? | `bash scripts/provision-platform-prereq.sh pg` (or `pg-core`). |
| Which default state key is used? | `oms/dev/postgresql-core.tfstate`. |
| Where is the canonical runbook? | `platform-prerequisites/terraform/README.md`. |
| New to a term here (root, state key, tfvars)? | [Glossary](../../../docs/references/glossary.md#terraform-basics). |

## Standard Use

1. Copy local vars file:

```bash
cp platform-prerequisites/terraform/postgresql-core/terraform.tfvars.sample platform-prerequisites/terraform/postgresql-core/terraform.tfvars
```

2. Fill required values (`vpc_id`, `database_subnet_ids`, `allowed_source_security_group_id`, `cnpg_backup_bucket_name`, `postgresql_operator_iam_role_arn`, `cluster_kms_key_arn`, `aurora_engine_version`).
3. Run from repository root:

```bash
bash scripts/provision-platform-prereq.sh pg
```

## Boundaries
- Do not reuse this root's state key for `postgresql-brand` or the MongoDB root — each must stay independently destroyable.
- Do not commit `terraform.tfvars`.

## Post-Apply Validation (PostgreSQL Scope)

After Terraform apply succeeds, verify the Aurora cluster is healthy:

1. **Check cluster status:**
```bash
aws rds describe-db-clusters \
  --db-cluster-identifier "$(terraform output -raw cluster_identifier)" \
  --query 'DBClusters[0].Status' \
  --output text
# Expect: available
```

2. **Get endpoint:**
```bash
terraform output cluster_endpoint
```

3. **Or use the unified verification:**
```bash
scripts/verify-platform-health.sh
```

Full step-by-step: [Operator Runbook](../../../docs/guides/operator-runbook.md)

## Related Documentation

| Topic | Link |
|---|---|
| Full operator runbook | [docs/guides/operator-runbook.md](../../../docs/guides/operator-runbook.md) |
| Architecture reference | [docs/guides/architect-reference.md](../../../docs/guides/architect-reference.md) |
| Enterprise architecture (Aurora core/brand split rationale) | [docs/guides/enterprise-architecture.md](../../../docs/guides/enterprise-architecture.md) |
| Verification commands | [docs/references/verification-commands.md](../../../docs/references/verification-commands.md) |
| Configuration catalog | [docs/operations/dev-configuration-catalog.md](../../../docs/operations/dev-configuration-catalog.md) |
