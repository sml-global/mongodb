# Terraform PostgreSQL "Brand" Root

## Purpose
This directory is the PostgreSQL "brand" database Terraform root — a second,
independent Aurora database sibling to `postgresql-core`. It exists so that
a brand-database outage, misconfiguration, or accidental destroy cannot
affect the core database's availability, matching this repo's general
scope-separation philosophy (see the root `CLAUDE.md`).

Both roots invoke the same shared `../modules/postgresql` module with
different `name_prefix`/`aurora_database_name`/`aurora_instance_count`
values — they are not different code, just different instances of the same
Aurora shape.

## Read This First

| Question | Answer |
|---|---|
| What does this root provision? | A second, independent Aurora PostgreSQL subnet group, security group, cluster, and instance(s) — "brand" database. |
| Which script uses this root? | `bash scripts/provision-platform-prereq.sh pg-brand`. |
| Which default state key is used? | `oms/dev/postgresql-brand.tfstate` (matches `POSTGRESQL_BRAND_STATE_KEY` in `config/environments/*.env`). |
| Where is the canonical runbook? | `platform-prerequisites/terraform/README.md`. |
| New to a term here (root, state key, tfvars)? | [Glossary](../../../docs/references/glossary.md#terraform-basics). |

## Standard Use

1. Copy local vars file:

```bash
cp platform-prerequisites/terraform/postgresql-brand/terraform.tfvars.sample platform-prerequisites/terraform/postgresql-brand/terraform.tfvars
```

2. Fill required values (`vpc_id`, `database_subnet_ids`, `allowed_source_security_group_id`, `cluster_kms_key_arn`, `aurora_engine_version`).
3. Run from repository root:

```bash
bash scripts/provision-platform-prereq.sh pg-brand
```

## Boundaries
- Do not reuse this root's state key for `postgresql-core` — they must stay independently destroyable.
- Do not commit `terraform.tfvars`.
- This root has no CNPG operator IAM policy — brand has no in-cluster CNPG `Cluster` CR wired to it yet. If a brand-specific K8s workload identity is needed later, follow `postgresql-core/main.tf`'s `cnpg_backup_access` pattern.

## Related Documentation

| Topic | Link |
|---|---|
| Full operator runbook | [docs/guides/operator-runbook.md](../../../docs/guides/operator-runbook.md) |
| Architecture reference | [docs/guides/architect-reference.md](../../../docs/guides/architect-reference.md) |
| Enterprise architecture (Aurora brand DB rationale) | [docs/guides/enterprise-architecture.md](../../../docs/guides/enterprise-architecture.md) |
| Verification commands | [docs/references/verification-commands.md](../../../docs/references/verification-commands.md) |
