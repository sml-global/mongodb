# PostgreSQL Dev RDS Bootstrap Plan

> For this phase, implement only a Terraform example form for cost-focused dev PostgreSQL.

## Goal
Create a reusable Terraform example that provisions dev PostgreSQL 18 on RDS `db.t4g.small` using existing network subnets.

## Tasks

### Task 1: Add Terraform example scaffold
**Files:**
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/main.tf`
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/variables.tf`
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/outputs.tf`
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/terraform.tfvars.example`
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/README.md`

- [x] Provision `aws_db_instance` for PostgreSQL 18 with `db.t4g.small`.
- [x] Configure storage floor/cap (`20 -> 30` GB gp3).
- [x] Keep deployment private and single-AZ.
- [x] Attach dedicated security group.

### Task 2: Security and connectivity model
- [x] Allow inbound 5432 from app SG when provided.
- [x] Support optional CIDR-based ingress for controlled dev access.
- [x] Keep `publicly_accessible = false` by default.

### Task 3: Operator handoff docs
- [x] Document that subnets are reused and not created.
- [x] Document no-Secrets-Manager credential path and state-file tradeoff.
- [x] Provide copy-edit-run steps for `terraform.tfvars` workflow.
