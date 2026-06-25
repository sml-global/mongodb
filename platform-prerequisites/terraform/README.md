# Platform Prerequisites Terraform

This directory is a reusable Terraform module for MongoDB platform prerequisites.

The module provisions:
- `mongodb` namespace
- MongoDB workload ServiceAccount (`psmdb-db` by default)
- IAM role for S3/KMS access
- EKS Pod Identity association (default) or IRSA annotation mode
- PBM S3 bucket with baseline security controls

## Usage
For manual-first dev deployment, use the wrapper example:

1. Copy `examples/dev/terraform.tfvars.example` to `examples/dev/terraform.tfvars` and update values.
2. Run the repo script:

```bash
scripts/run-platform-prereq.sh
```

The script runs `terraform init`, `fmt`, `validate`, and `plan` in one go against `examples/dev`.

## Additional Example: Dev PostgreSQL (RDS)
For a cost-focused dev PostgreSQL 18 form (RDS `db.t4g.small`) using existing subnets, see:

- `platform-prerequisites/terraform/examples/dev-postgresql`

## Access Requirement (Important)
The IAM identity running Terraform must have Kubernetes API authorization in the target EKS cluster.

- For automated pipelines later: create an EKS Access Entry (or equivalent RBAC mapping) for the CI IAM role.
- For current manual-first flow: ensure your bastion/admin IAM identity is mapped with permissions to create namespace and service account resources.

Without EKS API authorization, Terraform can authenticate to AWS but Kubernetes resources (such as `kubernetes_namespace`) will fail with Unauthorized/Forbidden errors.

## Standalone Module Intent
This module is intentionally clean for easy merge into a central Terraform platform project later. The `examples/dev` wrapper is temporary and can be discarded after integration.