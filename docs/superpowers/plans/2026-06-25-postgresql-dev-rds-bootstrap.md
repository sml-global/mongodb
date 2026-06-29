# PostgreSQL Dev Aurora Bootstrap Plan

> For this phase, implement only a Terraform example form for cost-focused dev Aurora PostgreSQL.

## Goal
Create a reusable Terraform example that provisions dev Aurora PostgreSQL with single writer and 1 ACU floor/cap using existing network subnets.

## Tasks

### Task 1: Add Terraform example scaffold
**Files:**
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/main.tf`
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/variables.tf`
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/outputs.tf`
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/terraform.tfvars.example`
- Create: `platform-prerequisites/terraform/examples/dev-postgresql/README.md`

- [x] Provision `aws_rds_cluster` + single `aws_rds_cluster_instance` writer.
- [x] Configure Serverless v2 capacity floor/cap (`1 -> 1` ACU).
- [x] Keep deployment private with single writer topology.
- [x] Attach dedicated security group.

### Task 2: Security and connectivity model
- [x] Allow inbound 5432 from app SG when provided.
- [x] Support optional CIDR-based ingress for controlled dev access.
- [x] Keep `publicly_accessible = false` by default on writer instance.

### Task 3: Operator handoff docs
- [x] Document that subnets are reused and not created.
- [x] Document dev manual-credential path, state-file tradeoff, and future production Secrets Manager direction.
- [x] Provide copy-edit-run steps for `terraform.tfvars` workflow.

### Task 4: Authentication posture decision (this phase)
- [x] Keep IAM DB authentication out of scope for this phase.
- [x] Keep static dev credentials as explicit temporary tradeoff.
- [x] Record production direction to managed credentials in docs/spec.
