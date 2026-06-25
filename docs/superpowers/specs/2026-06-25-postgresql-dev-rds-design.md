# PostgreSQL Dev RDS Design (PG18)

## Scope
- Add a dedicated Terraform form for dev PostgreSQL in this repository.
- Use Amazon RDS PostgreSQL (not Aurora) to minimize dev cost.
- Reuse existing VPC and existing private subnets; do not create subnet resources.

## Design Decisions
- Engine: `postgres`, version `18`
- Instance class: `db.t4g.small`
- Storage: `gp3`, 20 GB initial, autoscaling cap 30 GB
- Deployment mode: Single-AZ, non-public
- Backups/ops: 1-day retention, no Performance Insights, no Enhanced Monitoring
- Security group: dedicated DB SG; allow inbound 5432 from app SG and/or approved CIDRs
- Credentials: manual username/password variables (no Secrets Manager) for dev cost control

## Security and Trade-offs
- Password is not committed to git when provided via local `terraform.tfvars`.
- Password is still present in Terraform state and must be protected.
- Public access remains disabled by default.

## Implementation Artifacts
- `platform-prerequisites/terraform/examples/dev-postgresql/main.tf`
- `platform-prerequisites/terraform/examples/dev-postgresql/variables.tf`
- `platform-prerequisites/terraform/examples/dev-postgresql/outputs.tf`
- `platform-prerequisites/terraform/examples/dev-postgresql/terraform.tfvars.example`
- `platform-prerequisites/terraform/examples/dev-postgresql/README.md`

## Out of Scope
- Aurora cluster resources.
- Subnet creation.
- Kubernetes in-cluster PostgreSQL deployment.
