# Platform Prerequisites Terraform

## Overview
This directory contains Terraform for MongoDB platform prerequisites used by this repository.

What this setup is for:
- create/prepare namespace and ServiceAccount wiring for MongoDB workloads
- provision IAM + Pod Identity/IRSA access for PBM backup path
- provision PBM S3 bucket baseline controls

What this setup is not for:
- MongoDB workload manifests themselves (those are in `k8s/`)
- CI/CD automation (manual-first dev flow only)

## Table Of Contents
- [Overview](#overview)
- [Folder Map](#folder-map)
- [Naming Standard Alignment](#naming-standard-alignment)
- [Quick Start](#quick-start)
- [Executable Runbook](#executable-runbook)
- [Configuration Files](#configuration-files)
- [Dev PostgreSQL Example](#dev-postgresql-example)
- [Access Requirement](#access-requirement)
- [Standalone Module Intent](#standalone-module-intent)

## Folder Map

| Folder | Purpose |
|---|---|
| `platform-prerequisites/terraform` | Reusable Terraform module (no provider/backend lock-in). |
| `platform-prerequisites/terraform/examples/dev` | Manual-first dev wrapper used by local operators. |
| `platform-prerequisites/terraform/examples/dev-postgresql` | Optional dev PostgreSQL 18 example (RDS) for local testing. |

## Naming Standard Alignment
Naming follows the parent naming convention design:
- source: `/Users/frank/sml/oms/tf_generator/docs/designs/naming-convention-design.md`
- canonical pattern: `{provider}-{location}{site}-{env}-{app}-{role}-{type}-{seq}`

Current dev PBM bucket default:
- `sml-aw-gb0-d-oms-gen-s3-01`

Why this value:
- `sml` org prefix for global-namespace resources (S3)
- `aw-gb0-d-oms-gen-s3-01` follows the 7-segment model

## Quick Start
For manual-first dev deployment:

1. Copy `examples/dev/terraform.tfvars.example` to `examples/dev/terraform.tfvars`.
2. Edit `examples/dev/terraform.tfvars` values if needed.
3. Run:

```bash
scripts/run-platform-prereq.sh
```

4. Apply planned infrastructure:

```bash
cd platform-prerequisites/terraform/examples/dev && terraform apply tfplan
```

## Executable Runbook

| Command / Script | What It Does | When To Use |
|---|---|---|
| `scripts/run-platform-prereq.sh` | Runs `terraform init`, `fmt`, `validate`, and `plan` for `examples/dev`. | First step before any apply; rerun after variable/module changes. |
| `cd platform-prerequisites/terraform/examples/dev && terraform apply tfplan` | Applies the prepared dev plan. | After reviewing the generated plan and confirming environment values. |
| `scripts/bootstrap-dev-secrets.sh` | Creates missing dev secrets (`psmdb-encryption-key`, `psmdb-secrets`) without mutating tracked manifests. | Before applying MongoDB overlay or when secrets are missing. |
| `scripts/validate-dev-render.sh` | Offline render check for dev overlay. | Fast local verification before `kubectl apply` or commit. |
| `scripts/verify-dev-identity.sh` | Verifies MongoDB pods use expected ServiceAccount. | Post-deploy runtime check in cluster. |

## Configuration Files

| File | Category | Editable Settings | How To Change |
|---|---|---|---|
| `platform-prerequisites/terraform/variables.tf` | Module defaults | Namespace, SA name, PBM bucket, IAM role defaults, identity mode flags | Edit tracked defaults in git (shared baseline). |
| `platform-prerequisites/terraform/examples/dev/variables.tf` | Dev wrapper defaults | `aws_region`, bucket default, namespace/SA defaults | Edit tracked defaults in git for repo baseline. |
| `platform-prerequisites/terraform/examples/dev/terraform.tfvars` | Local runtime values | Per-operator/per-environment overrides | Local file edit (not committed). |
| `platform-prerequisites/terraform/main.tf` | Module resources | IAM/S3/Kubernetes resources and wiring | Change only when infrastructure architecture changes. |
| `platform-prerequisites/terraform/examples/dev/main.tf` | Wrapper wiring | Provider setup + module input mapping | Change when wrapper structure changes. |
| `platform-prerequisites/terraform/examples/dev/outputs.tf` | Wrapper outputs | Exposed values after apply | Change when additional outputs are required. |

Reference for broader repo configuration catalog:
- `docs/operations/dev-configuration-catalog.md`

## Dev PostgreSQL Example
For a cost-focused dev PostgreSQL 18 form (RDS `db.t4g.small`) using existing subnets, see:
- `platform-prerequisites/terraform/examples/dev-postgresql`

Current posture:
- Dev phase uses manual credentials from local `terraform.tfvars` (no IAM DB auth in this phase).
- Future production should use managed credentials (for example Secrets Manager-backed workflow).

## Access Requirement
The IAM identity running Terraform must have Kubernetes API authorization in the target EKS cluster.

- For automated pipelines later: create an EKS Access Entry (or equivalent RBAC mapping) for the CI IAM role.
- For current manual-first flow: ensure your bastion/admin IAM identity is mapped with permissions to create namespace and service account resources.

Without EKS API authorization, Terraform can authenticate to AWS but Kubernetes resources (such as `kubernetes_namespace`) fail with Unauthorized/Forbidden errors.

## Standalone Module Intent
This module is intentionally clean for later merge into a central Terraform platform project.
The `examples/dev` wrapper is temporary and can be discarded after integration.