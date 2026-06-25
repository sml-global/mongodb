# Dev PostgreSQL (RDS) Terraform Example

This example provisions a low-cost dev PostgreSQL instance on RDS:
- Engine: PostgreSQL 18
- Instance: `db.t4g.small`
- Storage: `gp3`, 20 GB initial, autoscale to 30 GB
- Networking: existing VPC + existing private subnets
- Security: dedicated DB security group

## Important Notes
- This example does not create subnets. Provide existing subnet IDs in `terraform.tfvars`.
- This example does not use AWS Secrets Manager to avoid extra secret cost.
- The master password is stored in Terraform state when using `password`.

## Usage
1. Copy variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Edit `terraform.tfvars` with your VPC/subnet/security group and password values.

3. Run Terraform:

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
