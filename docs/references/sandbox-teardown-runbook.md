# Sandbox Teardown Runbook

**Status:** Manual, operator-executed procedure. No step in this runbook runs automatically —
every command below requires the platform owner to run it explicitly with real AWS
credentials for account `632674123947`.

**Why this exists:** the new Production VPC (`10.200.0.0/17`) fully replaces the `sandbox`
validation environment in the same AWS account, per
`docs/superpowers/specs/2026-07-29-vpc-subnet-and-boomi-routing-design.md`. This must be a
complete teardown with zero leftover resources before Production is provisioned.

## Prerequisites

- AWS credentials for account `632674123947`, region `us-east-1` (sandbox's region).
- Confirm you are targeting `sandbox`, not `prod`, `uat`, or `dev` — every command below
  operates on `platform-prerequisites/terraform/environments/sandbox/*.tfvars`.

**CONFIRM before proceeding:** every step below is destructive and irreversible once applied.
Do not run Step 1 until you have verified: (1) your AWS credentials target account
`632674123947`, (2) no one else depends on the current `sandbox` environment, and (3) you
intend to destroy it now, not just review the plan. Stop here if any of these are not true.

## Step 1: Destroy consumers first — `mongodb`

```bash
cd platform-prerequisites/terraform/mongodb
terraform init -reconfigure
terraform plan -destroy -var-file=../environments/sandbox/mongodb.tfvars -out=sandbox-mongodb-destroy.tfplan
# Review the plan output. It should show only sandbox-prefixed resources.
terraform apply sandbox-mongodb-destroy.tfplan
```

## Step 2: Destroy consumers — `postgresql`

```bash
cd platform-prerequisites/terraform/postgresql
terraform init -reconfigure
terraform plan -destroy -var-file=../environments/sandbox/postgresql.tfvars -out=sandbox-postgresql-destroy.tfplan
terraform apply sandbox-postgresql-destroy.tfplan
```

## Step 3: Destroy `workload-identity`

**Verified reason this comes before `eks-platform`, not before `mongodb`/`postgresql`:**
`platform-prerequisites/terraform/workload-identity/main.tf` creates `aws_iam_role.identity`
resources trusted by `pods.eks.amazonaws.com` (EKS Pod Identity), and
`environments/sandbox/mongodb.tfvars` / `environments/sandbox/postgresql.tfvars` reference
those exact roles (`operator_iam_role_arn`, `postgresql_operator_iam_role_arn`). Destroying
`workload-identity` before Steps 1-2 would revoke IAM permissions those operators need for
their own teardown mid-way through.

```bash
cd platform-prerequisites/terraform/workload-identity
terraform init -reconfigure
terraform plan -destroy -var-file=../environments/sandbox/workload-identity.tfvars -out=sandbox-workload-identity-destroy.tfplan
terraform apply sandbox-workload-identity-destroy.tfplan
```

## Step 4: Bypass the EFS `prevent_destroy` lifecycle guard, then destroy `eks-platform`

`platform-prerequisites/terraform/modules/efs/main.tf` sets
`lifecycle { prevent_destroy = true }` on `aws_efs_file_system.this`. This must stay `true`
permanently in the module (it protects the future Production EFS filesystem) — do **not**
edit the module file. Instead, override it for this one destroy operation only:

```bash
cd platform-prerequisites/terraform/eks-platform
terraform init -reconfigure

terraform plan -destroy \
  -var-file=../environments/sandbox/eks-platform.tfvars \
  -out=sandbox-eks-platform-destroy.tfplan
```

**This step will always fail with `Instance cannot be destroyed`, not conditionally.**
Verified against HashiCorp's own documentation (fetched 2026-07-29): *"When
`prevent_destroy` is set to `true`, Terraform rejects **plans** that would destroy the
infrastructure object... and returns an error."* Since the module's `prevent_destroy = true`
is never changed, `terraform plan -destroy` fails deterministically every time, not only
"if" it happens to fail. The state-rm + AWS CLI delete path below is not an optional
fallback — it is the officially documented method for this exact situation (HashiCorp's own
docs point to "Remove a resource from state" for precisely this case) and is the only path
that will work here:

```bash
cd platform-prerequisites/terraform/eks-platform
terraform state show 'module.efs[0].aws_efs_file_system.this'   # confirm the exact file system ID
terraform state rm 'module.efs[0].aws_efs_file_system.this'
aws efs delete-file-system --file-system-id <FILE_SYSTEM_ID_FROM_ABOVE> --region us-east-1
terraform plan -destroy -var-file=../environments/sandbox/eks-platform.tfvars -out=sandbox-eks-platform-destroy.tfplan
terraform apply sandbox-eks-platform-destroy.tfplan
```

## Step 5: Verify zero leftover resources

```bash
aws resourcegroupstaggingapi get-resources --region us-east-1 \
  --tag-filters Key=Environment,Values=sandbox --query 'ResourceTagMappingList[].ResourceARN'
```

CONFIRM the output is an empty list before proceeding to provision Production in this
account. If any resources remain, investigate and remove them manually before continuing —
do not provision Production until this returns empty.
