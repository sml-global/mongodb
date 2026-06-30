# Terraform MongoDB Root

## Purpose
This directory is the MongoDB-only runnable Terraform root.

Use it when you need MongoDB prerequisite changes without touching PostgreSQL resources.

## Read This First

| Question | Answer |
|---|---|
| What does this root provision? | MongoDB prerequisites from `platform-prerequisites/terraform/reusable`. |
| Which script uses this root? | `bash scripts/provision-platform-prereq.sh mongodb`. |
| Which default state key is used? | `oms/dev/mongodb/terraform.tfstate`. |
| Where is the canonical runbook? | `platform-prerequisites/terraform/README.md`. |

## Standard Use

1. Copy local vars file:

```bash
cp platform-prerequisites/terraform/mongodb/terraform.tfvars.sample platform-prerequisites/terraform/mongodb/terraform.tfvars
```

2. Fill required values (`cluster_name`, etc.).
3. Run from repository root:

```bash
bash scripts/provision-platform-prereq.sh mongodb
```

## Boundaries
- Do not reuse this root's state key for PostgreSQL or unified root.
- Do not commit `terraform.tfvars`.
