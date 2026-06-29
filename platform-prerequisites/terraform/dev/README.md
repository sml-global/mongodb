# Dev Root (Temporary)

This is a temporary root wrapper for manual-first deployment.

Use this now, then discard it after merging the reusable Terraform layer (`platform-prerequisites/terraform/reusable`) into your main Terraform project.

## Usage
1. Copy `terraform.tfvars.sample` to `terraform.tfvars`.
2. Update values.
3. Run from repo root:

```bash
scripts/run-platform-prereq.sh
```
