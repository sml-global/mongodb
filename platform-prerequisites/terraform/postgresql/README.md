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
