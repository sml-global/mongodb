# Platform Prerequisites Terraform

## Purpose

This Terraform stack provisions the **OMS data-layer prerequisites** in the dev environment:
- **MongoDB** (Percona on EKS) — audit trail database for immutable compliance event records.
- **PostgreSQL** (Aurora) — primary application database for orders, inventory, and operational data.
- **SigNoz** — application telemetry (traces, metrics, logs) — provisioned via Kubernetes manifests only (no Terraform prerequisites).

## Documentation Has Moved

This file previously contained the full operator runbook (1300+ lines). That content has been split into focused, persona-based guides. Use the links below to find what you need.

### Start Here

| I am a... | I want to... | Read this |
|---|---|---|
| **Infra Operator** | Provision and troubleshoot | [Environment Setup](../../docs/guides/environment-setup.md) → [Operator Runbook](../../docs/guides/operator-runbook.md) |
| **Infra Architect** | Understand architecture and maintain | [Component Catalog](../../docs/references/component-catalog.md) → [Architect Reference](../../docs/guides/architect-reference.md) |
| **Boomi Admin** | Write audit logs and use telemetry | [Boomi Integration Guide](../../docs/guides/boomi-integration-guide.md) |
| **Enterprise Architect** | Review design, security, compliance | [Enterprise Architecture](../../docs/guides/enterprise-architecture.md) |

### Quick Reference

| Topic | Link |
|---|---|
| Central docs hub | [docs/index.md](../../docs/index.md) |
| Environment setup | [docs/guides/environment-setup.md](../../docs/guides/environment-setup.md) |
| Operator runbook | [docs/guides/operator-runbook.md](../../docs/guides/operator-runbook.md) |
| Architecture and state model | [docs/guides/architect-reference.md](../../docs/guides/architect-reference.md) |
| Component catalog | [docs/references/component-catalog.md](../../docs/references/component-catalog.md) |
| Verification commands | [docs/references/verification-commands.md](../../docs/references/verification-commands.md) |
| Recovery procedures | [docs/references/recovery-procedures.md](../../docs/references/recovery-procedures.md) |
| Configuration defaults | [docs/operations/dev-configuration-catalog.md](../../docs/operations/dev-configuration-catalog.md) |
| Enterprise architecture | [docs/guides/enterprise-architecture.md](../../docs/guides/enterprise-architecture.md) |
| Boomi integration | [docs/guides/boomi-integration-guide.md](../../docs/guides/boomi-integration-guide.md) |

## Scope

This stack provisions:
- MongoDB (audit trail) prerequisites on EKS: namespace, ServiceAccount/IAM wiring, PBM backup bucket
- Aurora PostgreSQL (primary app database) for dev: cluster with single writer instance

This stack does not provision:
- MongoDB workload manifests under `k8s/` (applied after prerequisites)
- Percona Operator manifests under `gitops/` (applied via Flux)
- Kyverno policies under `policies/` (applied separately)
- SigNoz telemetry under `gitops/signoz/` (no Terraform prerequisites)

## Key Terms

| Term | Meaning |
|---|---|
| Terraform root | A folder where Terraform runs for one scope |
| Scope | `all`, `mongodb`, or `pg` — selects root and state key |
| Terraform state | S3-stored record of created infrastructure |
| Reusable layer | Shared module code (no provider/backend lock-in) |
| Escrow file | Local-only secret backup on your workstation |

## Quick Start

```bash
# 1. Setup environment (once)
# See: docs/guides/environment-setup.md

# 2. Create tfvars
cp platform-prerequisites/terraform/mongodb/terraform.tfvars.sample platform-prerequisites/terraform/mongodb/terraform.tfvars

# 3. Fill required values
nano platform-prerequisites/terraform/mongodb/terraform.tfvars

# 4. Provision
bash scripts/provision-platform-prereq.sh mongodb

# 5. Bootstrap secrets (MongoDB scope only)
scripts/bootstrap-dev-secrets.sh

# 6. Validate
scripts/validate-dev-render.sh

# 7. Verify
scripts/verify-platform-health.sh
```

Full step-by-step: [Operator Runbook](../../docs/guides/operator-runbook.md)

## Terraform Roots

| Root | Scope | State Key |
|---|---|---|
| `platform-prerequisites/terraform/mongodb` | `mongodb` | `oms/dev/mongo.tfstate` |
| `platform-prerequisites/terraform/postgresql` | `pg` | `oms/dev/pg.tfstate` |
| `platform-prerequisites/terraform/reusable` | (shared module, not runnable) | N/A |

Full architecture: [Architect Reference](../../docs/guides/architect-reference.md)
