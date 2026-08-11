# DEV Terraform State Archive (v0.9 snapshot)

This directory is a frozen, point-in-time archive of DEV's Terraform state as it
existed on 2026-08-11, captured ahead of a planned Terraform refactor that will
change resource addressing/module structure across all environments (dev, uat,
prod). It exists so that, later, DEV's current infrastructure can still be
destroyed cleanly using the **old** Terraform code + **old** state, even after
`main` has moved on to the new, refactored code.

**This archive does not modify DEV in any way.** Everything here was produced by
read-only `terraform state list` / `terraform show -json` / `aws s3 cp` calls
against the live `sml-oms-dev-tfstate` S3 bucket. Per this repo's absolute
safety rule (see `CLAUDE.md`), DEV (account `815402439714`) must never be
provisioned, destroyed, or modified — this archive is inventory/backup only.

**⚠️ Contains live plaintext secrets — deliberate, scoped exception.** The raw
`.tfstate` files (`dev-mongo.tfstate`, `dev-pg.tfstate`,
`dev-signoz-observability.tfstate`) contain real, unredacted sensitive values
as Terraform stores them natively — notably the Aurora `master_password` in
`dev-pg.tfstate` and a live EKS auth token in `dev-mongo.tfstate` (short-lived,
expired by the time you read this). These were committed unredacted, on
purpose, per an explicit decision (2026-08-11): this is DEV-only, for testing,
and the plan is to rotate/replace all DEV secrets when DEV is eventually
rebuilt, at which point everything in this snapshot becomes historical only.
Until that rebuild happens, treat this directory as sensitive — the Aurora
password here is valid against a still-live DEV database.

## Why this exists

The upcoming Terraform revamp affects every environment's module structure, not
just one. Once the refactor lands on `main`, the new Terraform code will no
longer match DEV's existing (pre-refactor) resource addresses in
`sml-oms-dev-tfstate`. Keeping this snapshot — old code (via the git tag below)
paired with the exact old state files — preserves the ability to run a real
`terraform destroy` against DEV's current infrastructure later, using the code
that actually matches that state, rather than trying to reconcile old
infrastructure against new, incompatible Terraform.

## What's in this directory

| File | Contents |
|---|---|
| `dev-mongo-state-list.txt` | `terraform state list` output for `oms/dev/mongo.tfstate` |
| `dev-mongo-state.json` | `terraform show -json` output (full resource detail incl. AWS IDs/ARNs) for the same state |
| `dev-pg-state-list.txt` | `terraform state list` output for `oms/dev/pg.tfstate` |
| `dev-pg-state.json` | `terraform show -json` output for the same state |
| `dev-signoz-state-list.txt` | `terraform state list` output for `oms/dev/signoz-observability.tfstate` |
| `dev-signoz-state.json` | `terraform show -json` output for the same state — **empty/0 bytes in this snapshot** (the export command did not complete successfully when captured); `dev-signoz-state-list.txt` and the raw `dev-signoz-observability.tfstate` are the authoritative records for this scope instead |
| `dev-mongo.tfstate` | Raw state file downloaded directly from S3 (`oms/dev/mongo.tfstate`) |
| `dev-pg.tfstate` | Raw state file downloaded directly from S3 (`oms/dev/pg.tfstate`) |
| `dev-signoz-observability.tfstate` | Raw state file downloaded directly from S3 (`oms/dev/signoz-observability.tfstate`) |
| `dev-terraform.tfstate` | Raw state file downloaded directly from S3 (`oms/dev/terraform.tfstate` — unscoped key, origin/owning Terraform root not yet identified, see #141) |

This git commit is tagged `dev-tfstate-archive-v0.9` — that tag, together with
this directory, is the durable reference point: check out the tag to get the
exact Terraform module code these state files were captured against.

## How to use this later, when DEV cleanup is authorized

**Do not run any of this until DEV modification is explicitly authorized** (a
deliberate, agreed change to `CLAUDE.md`'s current absolute DEV-restriction
rule — not a decision to make unilaterally in a coding session).

Once authorized, to destroy DEV's old infrastructure using this exact
snapshot:

```bash
git checkout dev-tfstate-archive-v0.9
cd platform-prerequisites/terraform/mongodb
terraform init -input=false
cp /path/to/platform-prerequisites/olddev/dev-mongo.tfstate ./terraform.tfstate
terraform plan -destroy   # review carefully before applying
terraform destroy
```

Repeat for the PostgreSQL and SigNoz scopes using their corresponding
downloaded `.tfstate` file, substituting the matching terraform root directory
in `cd` and the matching `cp` source file.

**Which terraform root owns `dev-pg.tfstate`?** Its `terraform state list`
(`dev-pg-state-list.txt`) shows `aws_rds_cluster.postgresql` — an AWS-managed
Aurora cluster — which structurally matches `platform-prerequisites/terraform/
postgresql-core/`. This is worth double-checking before use: per
`docs/references/postgresql-platform-contract.md` and this repo's CLAUDE.md,
DEV's PostgreSQL is documented as CNPG (self-managed, in-cluster), not Aurora —
so either that documentation is stale, or this state file represents an
earlier/different DEV PostgreSQL setup than what's currently documented as
canonical for DEV. Confirm which is true before running `terraform destroy`
against it — see the open question filed in #141.

For `dev-signoz-observability.tfstate`, use
`platform-prerequisites/terraform/signoz-observability/`.

The `dev-terraform.tfstate` file (unscoped key, no resources — confirmed empty
via direct S3 read, `"resources": []`) needs no destroy action; it is not
associated with any live infrastructure.

## Manual S3 cleanup (after Terraform destroy has fully succeeded, or if bypassing Terraform entirely)

**Only do this after confirming, via `terraform state list` (should return
empty) or live AWS console/CLI checks, that the real infrastructure this state
describes has actually been destroyed.** Deleting the state file does **not**
delete the underlying AWS resources — it only removes Terraform's own record
of them. Deleting state before destroying real infra will orphan that infra
(nothing will track or manage it anymore).

To remove the old, now-superseded state objects directly from S3 once their
real infrastructure is confirmed gone:

```bash
# Confirm the objects that exist today (sanity check before deleting):
aws s3 ls s3://sml-oms-dev-tfstate/oms/dev/ --recursive

# Delete each old state object individually (never use a wildcard/recursive
# delete on this bucket — confirm each key explicitly):
aws s3 rm s3://sml-oms-dev-tfstate/oms/dev/mongo.tfstate
aws s3 rm s3://sml-oms-dev-tfstate/oms/dev/pg.tfstate
aws s3 rm s3://sml-oms-dev-tfstate/oms/dev/signoz-observability.tfstate
aws s3 rm s3://sml-oms-dev-tfstate/oms/dev/terraform.tfstate

# If versioning is enabled on this bucket, `aws s3 rm` only creates a delete
# marker -- the prior version remains recoverable. To confirm:
aws s3api get-bucket-versioning --bucket sml-oms-dev-tfstate

# To permanently purge a specific old version (only if truly certain, and only
# after the corresponding infra is destroyed):
aws s3api list-object-versions --bucket sml-oms-dev-tfstate --prefix oms/dev/mongo.tfstate
aws s3api delete-object --bucket sml-oms-dev-tfstate --key oms/dev/mongo.tfstate --version-id <VERSION_ID>
```

Do this only after real infrastructure removal is independently confirmed —
this repo's own `terraform destroy` (or manual AWS resource deletion) must
happen first; deleting the state file is the very last step, not a substitute
for it.
