# Dev PostgreSQL (Aurora) Terraform Example

This example provisions a low-cost dev Aurora PostgreSQL cluster:
- Engine: Aurora PostgreSQL (`aurora-postgresql`)
- Topology: single writer instance (no readers)
- Capacity: Aurora Serverless v2 with `min_acu = 1`, `max_acu = 1` (approximately 2 GiB equivalent memory)
- Networking: existing VPC + existing private subnets
- Security: dedicated DB security group

## Important Notes
- This example does not create subnets. Provide existing subnet IDs in `terraform.tfvars`.
- This example does not use AWS Secrets Manager because this phase is dev-only and optimized for minimal operational friction.
- The master password is stored in Terraform state when using `password`.
- IAM DB authentication is intentionally not used in this phase.
- Aurora storage remains distributed by Aurora design, even with a single writer instance.
- Production guidance: use managed credentials (for example `manage_master_user_password = true`) and avoid shared static passwords.

## Usage
1. Copy variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Edit `terraform.tfvars` with your VPC/subnet/security group and password values.
	- Keep `terraform.tfvars` local and out of git.

3. Run Terraform:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
