# Terraform Dev Root

## Purpose
This directory is the runnable Terraform root for the dev environment.

It provisions MongoDB platform prerequisites and Aurora PostgreSQL in one Terraform plan, apply, and state file.

## Read This First

| Question | Answer |
|---|---|
| What is this directory? | The Terraform execution root used by `scripts/run-platform-prereq.sh`. |
| When should I edit files here? | When changing dev root inputs, providers, backend wiring, PostgreSQL resources, or root outputs. |
| Where should I run commands from? | Run the wrapper from the repository root. Terraform itself executes in this directory. |
| Which state owns this root? | The unified MongoDB + PostgreSQL state, local for throwaway testing or S3 for shared environments. |
| What is the canonical guide? | `platform-prerequisites/terraform/README.md`. |

## Files

| File | Purpose |
|---|---|
| `main.tf` | Providers, backend declaration, MongoDB reusable layer call, and PostgreSQL resources. |
| `variables.tf` | Input contract for MongoDB prerequisites, AWS networking, and PostgreSQL sizing/credentials. |
| `outputs.tf` | Outputs for MongoDB prerequisites and PostgreSQL endpoints/resource IDs. |
| `terraform.tfvars.sample` | Local operator template. Copy to `terraform.tfvars` and fill real values. |

## Standard Use

1. Complete workstation setup in `platform-prerequisites/terraform/README.md`.
2. Copy `terraform.tfvars.sample` to `terraform.tfvars`.
3. Fill real environment values.
4. Run from the repository root:

```bash
scripts/run-platform-prereq.sh
```

5. Review and apply the generated plan:

```bash
cd platform-prerequisites/terraform/dev && terraform apply tfplan
```

## Boundaries

- Do not commit `terraform.tfvars`.
- Do not run this root with a different state key unless you are intentionally creating or migrating an environment.
- Keep shared MongoDB prerequisite logic in `platform-prerequisites/terraform/reusable` unless the change is root-specific.
