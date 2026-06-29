# PostgreSQL Dev Aurora Design

## Scope
- Add a dedicated Terraform form for dev PostgreSQL in this repository.
- Use Amazon Aurora PostgreSQL with a single writer instance for dev.
- Reuse existing VPC and existing private subnets; do not create subnet resources.

## Design Decisions
- Engine: `aurora-postgresql`
- Engine version: optional input (`null` default to region default)
- Capacity mode: Aurora provisioned instance class (`db.t4g.medium` default)
- Deployment mode: single writer instance, non-public
- Backups/ops: 1-day retention, no Performance Insights, no Enhanced Monitoring
- Security group: dedicated DB SG; allow inbound 5432 from app SG and/or approved CIDRs
- Credentials: manual username/password variables for dev phase (no Secrets Manager and no IAM DB auth in this phase)
- Production posture (future): move to managed credentials via Secrets Manager-backed workflow

## Security and Trade-offs
- Password is not committed to git when provided via local `terraform.tfvars`.
- Password is still present in Terraform state and must be protected.
- Public access remains disabled by default.
- Aurora storage remains distributed by Aurora design even with a single writer.
- This is an explicit dev tradeoff to prioritize operational simplicity over state-file secrecy.

## Implementation Artifacts
- `platform-prerequisites/terraform/examples/dev-postgresql/main.tf`
- `platform-prerequisites/terraform/examples/dev-postgresql/variables.tf`
- `platform-prerequisites/terraform/examples/dev-postgresql/outputs.tf`
- `platform-prerequisites/terraform/examples/dev-postgresql/terraform.tfvars.example`
- `platform-prerequisites/terraform/examples/dev-postgresql/README.md`

## Out of Scope
- Multi-writer/read replica topology.
- Subnet creation.
- Kubernetes in-cluster PostgreSQL deployment.
