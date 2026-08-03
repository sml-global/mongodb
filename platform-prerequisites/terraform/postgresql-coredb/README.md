# Terraform PostgreSQL Core-DB (CNPG) Root

## Purpose
This directory is the dev/SIT CNPG "core" database prerequisites root: namespace, S3 backup bucket, and IAM pod-identity role for the `coredb` CNPG cluster.

This is **not** the Aurora root — `platform-prerequisites/terraform/postgresql-core` provisions Aurora for UAT/Prod. This root exists so the core CNPG cluster (dev/SIT) can be provisioned, resized, or destroyed independently of the brand CNPG cluster (`postgresql-branddb`).

## Read This First

| Question | Answer |
|---|---|
| What does this root provision? | Namespace, S3 backup bucket, and IAM pod-identity role for the core CNPG cluster, from `platform-prerequisites/terraform/modules/cnpg-prereqs`. |
| Which script uses this root? | `bash scripts/provision-platform-prereq.sh pg-coredb`. |
| Which default state key is used? | `oms/dev/postgresql-coredb.tfstate`. |
| Which namespace does it create? | `coredb` (see `namespace` variable). |
| New to a term here (root, state key, tfvars)? | [Glossary](../../../docs/references/glossary.md#terraform-basics). |

## Standard Use

1. Copy local vars file:

```bash
cp platform-prerequisites/terraform/postgresql-coredb/terraform.tfvars.sample platform-prerequisites/terraform/postgresql-coredb/terraform.tfvars
```

2. Fill required values (`cluster_name`, `backup_bucket_name`, etc.).
3. Run from repository root:

```bash
bash scripts/provision-platform-prereq.sh pg-coredb
```

4. Apply the CNPG Cluster CR itself (separate from this Terraform root):

```bash
kubectl apply -k gitops/postgresql-coredb/overlays/dev
```

## Boundaries
- Do not reuse this root's state key for the brand CNPG root (`postgresql-branddb`) or the Aurora roots (`postgresql-core`/`postgresql-brand`).
- Do not commit `terraform.tfvars`.

## Related Documentation

| Topic | Link |
|---|---|
| Full operator runbook | [docs/guides/operator-runbook.md](../../../docs/guides/operator-runbook.md) |
| Architecture reference | [docs/guides/architect-reference.md](../../../docs/guides/architect-reference.md) |
| Verification commands | [docs/references/verification-commands.md](../../../docs/references/verification-commands.md) |
