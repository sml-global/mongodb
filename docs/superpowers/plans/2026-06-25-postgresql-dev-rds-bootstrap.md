# PostgreSQL Dev Aurora Bootstrap Plan

## Document Status
This is a historical implementation plan. It is retained for traceability and should not be used as the current operator runbook.

Current implementation uses the unified Terraform root at `platform-prerequisites/terraform/dev`; current operator instructions are maintained in `platform-prerequisites/terraform/README.md`.

> For this phase, implement only a Terraform root form for cost-focused dev Aurora PostgreSQL.

## Goal
Create a reusable Terraform root that provisions dev Aurora PostgreSQL with a single writer and provisioned instance class using existing network subnets.

## Tasks

### Task 1: Add Terraform root scaffold
**Files:**
- Modify: `platform-prerequisites/terraform/dev/main.tf`
- Modify: `platform-prerequisites/terraform/dev/variables.tf`
- Modify: `platform-prerequisites/terraform/dev/outputs.tf`
- Modify: `platform-prerequisites/terraform/dev/terraform.tfvars.sample`
- Modify: `platform-prerequisites/terraform/README.md`

- [x] Provision `aws_rds_cluster` + single `aws_rds_cluster_instance` writer.
- [x] Configure provisioned writer instance class (`db.t4g.medium` default).
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
