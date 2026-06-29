# Platform Prerequisites Terraform

## Overview
This directory contains Terraform prerequisites used by this repository for both:
- MongoDB on EKS
- PostgreSQL on Aurora PostgreSQL (dev path)

What this setup is for:
- create/prepare namespace and ServiceAccount wiring for MongoDB workloads
- provision IAM + Pod Identity/IRSA access for PBM backup path
- provision PBM S3 bucket baseline controls
- provision optional dev Aurora PostgreSQL resources

What this setup is not for:
- MongoDB workload manifests themselves (those are in `k8s/`)
- CI/CD automation (manual-first dev flow only)

## Table Of Contents
- [Platform Prerequisites Terraform](#platform-prerequisites-terraform)
  - [Overview](#overview)
  - [Table Of Contents](#table-of-contents)
  - [Folder Map](#folder-map)
  - [Naming Standard Alignment](#naming-standard-alignment)
  - [Why Separate Roots Exist](#why-separate-roots-exist)
  - [S3 State Backend Migration](#s3-state-backend-migration)
  - [Quick Start: MongoDB Prerequisites](#quick-start-mongodb-prerequisites)
  - [Quick Start: PostgreSQL Prerequisites](#quick-start-postgresql-prerequisites)
  - [Executable Runbook](#executable-runbook)
  - [Configuration Files](#configuration-files)
  - [Dev PostgreSQL Path](#dev-postgresql-path)
  - [Access Requirement](#access-requirement)
  - [Standalone Module Intent](#standalone-module-intent)

## Folder Map

| Folder | Purpose |
|---|---|
| `platform-prerequisites/terraform/reusable` | Reusable Terraform layer (no provider/backend lock-in). |
| `platform-prerequisites/terraform/dev` | Manual-first MongoDB prerequisite root used by local operators. |
| `platform-prerequisites/terraform/dev-postgresql` | Manual-first Aurora PostgreSQL root used by local operators. |

## Naming Standard Alignment
Naming follows the parent naming convention design:
- source: `naming-convention-design.md` in the `tf_generator` repository
- canonical pattern: `{provider}-{location}{site}-{env}-{app}-{role}-{type}-{seq}`

Current dev PBM bucket default:
- `sml-aw-gb0-d-oms-gen-s3-01`

Why this value:
- `sml` org prefix for global-namespace resources (S3)
- `aw-gb0-d-oms-gen-s3-01` follows the 7-segment model

## Why Separate Roots Exist
Short answer: `platform-prerequisites/terraform/reusable` is intentionally a reusable Terraform layer, while `dev/*` roots are runnable Terraform entrypoints.

Why it is split:
- Reusable Terraform layer (`platform-prerequisites/terraform/reusable`):
  - keeps resources portable and easy to merge into a central platform repo
  - avoids locking this module to one local backend/provider/runtime shape
- Runnable roots (`dev`, `dev-postgresql`):
  - provides providers and concrete root-level execution context
  - gives operators a ready-to-run manual workflow for this repo

Can we run directly from `platform-prerequisites/terraform/reusable`?
- Not recommended in current layout.
- You would have to turn it into a root stack (provider/backend/root inputs), which reduces reusability.
- If you want that model, we can flatten it in a follow-up change and drop the wrappers.

## S3 State Backend Migration

Yes, this repository now supports one-time, idempotent state migration to S3.

Script added:
- `scripts/bootstrap-terraform-s3-backend.sh`

What it does:
- Checks if the state bucket exists; creates it if missing.
- Applies bucket baseline controls after creation:
  - versioning enabled
  - server-side encryption (AES256)
  - public access block enabled
- Checks whether the remote state object already exists.
- If remote exists: configures Terraform to use it (no migration).
- If remote missing and local `terraform.tfstate` exists: migrates local state once.
- If both missing: initializes a fresh remote backend (empty state).

One-time setup (MongoDB root):

```bash
export TF_STATE_BUCKET="your-terraform-state-bucket"
export TF_STATE_REGION="us-east-1"
export TF_STATE_KEY="mongodb/platform-prerequisites/dev/terraform.tfstate"

scripts/run-platform-prereq.sh
```

One-time setup (PostgreSQL root):

```bash
export TF_STATE_BUCKET="your-terraform-state-bucket"
export TF_STATE_REGION="us-east-1"
export TF_STATE_KEY="mongodb/platform-prerequisites/dev-postgresql/terraform.tfstate"

scripts/run-platform-prereq-postgresql.sh
```

Later runs:
- Keep `TF_STATE_BUCKET` set.
- The scripts detect existing remote state and reuse it.
- Bucket creation and migration are skipped when already done.

If `TF_STATE_BUCKET` is not set:
- scripts fall back to local state behavior.

## Quick Start: MongoDB Prerequisites
For manual-first MongoDB prerequisite deployment:

1. Copy `dev/terraform.tfvars.sample` to `dev/terraform.tfvars`.
2. Edit `dev/terraform.tfvars` values if needed.
3. Run:

```bash
scripts/run-platform-prereq.sh
```

4. Apply planned infrastructure:

```bash
cd platform-prerequisites/terraform/dev && terraform apply tfplan
```

## Quick Start: PostgreSQL Prerequisites
For manual-first PostgreSQL dev deployment:

1. Copy `dev-postgresql/terraform.tfvars.sample` to `dev-postgresql/terraform.tfvars`.
2. Edit `dev-postgresql/terraform.tfvars` values.
3. Run:

```bash
scripts/run-platform-prereq-postgresql.sh
```

4. Apply planned infrastructure:

```bash
cd platform-prerequisites/terraform/dev-postgresql && terraform apply tfplan
```

## Executable Runbook

| Command / Script | What It Does | When To Use |
|---|---|---|
| `scripts/bootstrap-terraform-s3-backend.sh` | Ensures S3 backend bucket exists and performs one-time local-to-S3 state migration only when needed. | Before first remote-state run, or directly via wrapper scripts when `TF_STATE_BUCKET` is set. |
| `scripts/run-platform-prereq.sh` | Runs `terraform init`, `fmt`, `validate`, and `plan` for `dev`. | First step before any apply; rerun after variable/module changes. |
| `scripts/run-platform-prereq-postgresql.sh` | Runs `terraform init`, `fmt`, `validate`, and `plan` for `dev-postgresql`. | First step before PostgreSQL apply; rerun after PostgreSQL variable/module changes. |
| `cd platform-prerequisites/terraform/dev && terraform apply tfplan` | Applies the prepared MongoDB prerequisite plan. | After reviewing the generated plan and confirming environment values. |
| `cd platform-prerequisites/terraform/dev-postgresql && terraform apply tfplan` | Applies the prepared PostgreSQL plan. | After reviewing PostgreSQL plan and confirming DB inputs. |
| `scripts/bootstrap-dev-secrets.sh` | Creates missing dev secrets (`psmdb-encryption-key`, `psmdb-secrets`) without mutating tracked manifests. | Before applying MongoDB overlay or when secrets are missing. |
| `scripts/validate-dev-render.sh` | Offline render check for dev overlay. | Fast local verification before `kubectl apply` or commit. |
| `scripts/verify-dev-identity.sh` | Verifies MongoDB pods use expected ServiceAccount. | Post-deploy runtime check in cluster. |

## Configuration Files

| File | Category | Editable Settings | How To Change |
|---|---|---|---|
| `platform-prerequisites/terraform/reusable/variables.tf` | Module defaults | Namespace, SA name, PBM bucket, IAM role defaults, identity mode flags | Edit tracked defaults in git (shared baseline). |
| `platform-prerequisites/terraform/dev/variables.tf` | MongoDB root defaults | `aws_region`, bucket default, namespace/SA defaults | Edit tracked defaults in git for repo baseline. |
| `platform-prerequisites/terraform/dev/terraform.tfvars` | Local runtime values | Per-operator/per-environment overrides | Local file edit (not committed). |
| `platform-prerequisites/terraform/reusable/main.tf` | Module resources | IAM/S3/Kubernetes resources and wiring | Change only when infrastructure architecture changes. |
| `platform-prerequisites/terraform/dev/main.tf` | MongoDB root wiring | Provider setup + module input mapping | Change when root wiring changes. |
| `platform-prerequisites/terraform/dev/outputs.tf` | MongoDB root outputs | Exposed values after apply | Change when additional outputs are required. |
| `platform-prerequisites/terraform/dev-postgresql/variables.tf` | PostgreSQL root defaults | DB sizing/version/network/security defaults | Edit tracked defaults in git for PostgreSQL baseline. |
| `platform-prerequisites/terraform/dev-postgresql/main.tf` | PostgreSQL root resources | Aurora cluster/subnet group/security group resource definitions | Change when PostgreSQL infrastructure architecture changes. |
| `platform-prerequisites/terraform/dev-postgresql/outputs.tf` | PostgreSQL root outputs | Exposed PostgreSQL runtime values after apply | Change when additional PostgreSQL outputs are required. |

Reference for broader repo configuration catalog:
- `docs/operations/dev-configuration-catalog.md`

## Dev PostgreSQL Path
For a cost-focused dev Aurora PostgreSQL single-writer form using existing subnets, see:
- `platform-prerequisites/terraform/dev-postgresql`

Current posture:
- Dev phase uses manual credentials from local `terraform.tfvars` (no IAM DB auth in this phase).
- Future production should use managed credentials (Secrets Manager-backed workflow).

## Access Requirement
The IAM identity running Terraform must have Kubernetes API authorization in the target EKS cluster.

- For automated pipelines later: create an EKS Access Entry (or equivalent RBAC mapping) for the CI IAM role.
- For current manual-first flow: ensure your bastion/admin IAM identity is mapped with permissions to create namespace and service account resources.

Without EKS API authorization, Terraform can authenticate to AWS but Kubernetes resources (such as `kubernetes_namespace`) fail with Unauthorized/Forbidden errors.

## Standalone Module Intent
This module is intentionally clean for later merge into a central Terraform platform project.
The `dev` and `dev-postgresql` roots are local execution entrypoints and can be replaced by your central platform root configuration after integration.