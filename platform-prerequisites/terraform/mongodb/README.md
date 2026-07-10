# Terraform MongoDB Root

## Purpose
This directory is the MongoDB-only runnable Terraform root.

Use it when you need MongoDB prerequisite changes without touching PostgreSQL resources.

## Read This First

| Question | Answer |
|---|---|
| What does this root provision? | MongoDB prerequisites from `platform-prerequisites/terraform/reusable`. |
| Which script uses this root? | `bash scripts/provision-platform-prereq.sh mongodb`. |
| Which default state key is used? | `oms/dev/mongo.tfstate`. |
| Where is the canonical runbook? | `platform-prerequisites/terraform/README.md`. |
| New to a term here (root, state key, tfvars)? | [Glossary](../../../docs/references/glossary.md#terraform-basics). |

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
- Do not reuse this root's state key for the PostgreSQL root.
- Do not commit `terraform.tfvars`.

## Post-Apply Steps (MongoDB Scope)

After Terraform apply succeeds, complete these before MongoDB workload can run:

1. **Bootstrap secrets:**
```bash
scripts/bootstrap-dev-secrets.sh
```

2. **Validate overlay render:**
```bash
scripts/validate-dev-render.sh
```

3. **Apply workload manifests** (via `provision.sh` or manual):
```bash
bash scripts/provision-k8s-components.sh mongodb
```

4. **Verify health:**
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
| Recovery procedures | [docs/references/recovery-procedures.md](../../../docs/references/recovery-procedures.md) |
| Configuration catalog | [docs/operations/dev-configuration-catalog.md](../../../docs/operations/dev-configuration-catalog.md) |
