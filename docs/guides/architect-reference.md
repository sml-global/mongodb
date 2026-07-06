# Architect Reference

Architecture, state model, dependency graph, repository structure, and day-2 maintenance for the OMS data layer.

**Who this is for:** Infra Architects/Admins who design, maintain, and evolve the platform.

**Related docs:**
- [Component Catalog](../references/component-catalog.md) — detailed component descriptions
- [Verification Commands](../references/verification-commands.md) — per-component health checks
- [Enterprise Architecture](enterprise-architecture.md) — design decisions, security, compliance
- [Operator Runbook](operator-runbook.md) — step-by-step provisioning
- [Configuration Catalog](../operations/dev-configuration-catalog.md) — embedded defaults

---

## Architecture Summary

The OMS data layer separates shared Terraform logic from runnable roots and Kubernetes manifests.

```
platform-prerequisites/terraform/
  reusable/          ← Shared module: MongoDB prerequisites (IAM, S3, namespace, SA)
  mongodb/           ← Runnable root: MongoDB scope (state: oms/dev/mongo.tfstate)
  postgresql/        ← Runnable root: PostgreSQL scope (state: oms/dev/pg.tfstate)

k8s/
  base/              ← Base Kubernetes manifests (PSMDB CR, StorageClass, certs, PDB)
  overlays/dev/      ← Dev overlay patches (sizing, storage, backup config)

gitops/
  operators/base/    ← Percona Operator HelmRelease + HelmRepository
  signoz/base/       ← SigNoz HelmRelease + HelmRepository + namespace

policies/
  kyverno/           ← Admission policies (storage class, sidecar resources, secrets)

scripts/             ← All operational scripts (provision, bootstrap, validate, verify)
```

Execution contract:
- One selected root per run (`mongodb` or `postgresql`; `all` runs both)
- One plan artifact (`tfplan`) in that root
- One state key for that root

## Dependency Graph

```mermaid
flowchart TD
  EKS[EKS Cluster pre-existing]

  EKS --> EBSCSI[AWS EBS CSI Driver]
  EKS --> FLUX[Flux Controllers]
  EKS --> KYVERNO[Kyverno]
  EKS --> CERTMGR[cert-manager]
  EKS --> PODID[EKS Pod Identity Agent]

  EBSCSI --> SC[StorageClass gp3-mongodb]
  SC --> PVCS[PVCs]

  FLUX --> PERCONA_OP[Percona Operator]
  FLUX --> SIGNOZ_HR[SigNoz HelmRelease]

  CERTMGR --> CERTS[MongoDB TLS Certs]

  subgraph terraform[Terraform Provisioned]
    NS[mongodb namespace]
    SA[ServiceAccount + IAM Role]
    PBM[PBM S3 Bucket]
    AURORA[Aurora PostgreSQL]
    TFSTATE[S3 State Backend]
  end

  subgraph k8s_workloads[Kubernetes Workloads]
    PERCONA_OP --> PSMDB[MongoDB ReplicaSet]
    CERTS --> PSMDB
    PVCS --> PSMDB
    PVCS --> SIGNOZ_HR
    SA --> PSMDB
  end

  PODID --> SA
  KYVERNO --> POLICIES[Admission Policies]
  POLICIES --> PSMDB
```

## State Partitioning Strategy

Terraform root and state key are selected by script scope:

| Scope | Terraform Root | State Key |
|---|---|---|
| `all` | Runs `mongodb` then `pg` sequentially | Two separate keys |
| `mongodb` | `platform-prerequisites/terraform/mongodb` | `oms/dev/mongo.tfstate` |
| `pg` | `platform-prerequisites/terraform/postgresql` | `oms/dev/pg.tfstate` |

Safety rules:
- `all` is a shortcut that runs both — does not create a third state
- Each scope always uses its own root and state key
- Never reuse one state key across multiple roots

## State Backend Strategy

Backend migration is intentionally idempotent. Script: `scripts/bootstrap-terraform-s3-backend.sh`

```mermaid
flowchart TD
  A[Script uses TF_STATE_BUCKET default: sml-oms-dev-tfstate] --> B{S3 bucket exists?}
  B -->|No| C[Create bucket + controls versioning/encryption/public-block]
  B -->|Yes| D[Reuse existing bucket]
  C --> E{Remote state object exists?}
  D --> E
  E -->|Yes| F[terraform init -reconfigure]
  E -->|No remote + local exists| G[terraform init -migrate-state once]
  E -->|Neither exists| H[terraform init fresh]
  F --> I[Ready for plan]
  G --> I
  H --> I
```

Important rules:
- Keep the same `TF_STATE_KEY` for the same environment
- Changing the key splits infrastructure ownership
- Migration is one-time; later runs reuse remote state

## Terraform Provisioning Model

```mermaid
flowchart TD
  A[scripts/provision-platform-prereq.sh scope] --> B{scope}
  B -->|all| C[Run mongodb then pg]
  B -->|mongodb| D[Root: mongodb]
  B -->|pg| E[Root: postgresql]
  C --> D
  C --> E
  D --> G[State key: oms/dev/mongo.tfstate]
  E --> H[State key: oms/dev/pg.tfstate]
  G --> I[Plan and apply]
  H --> I
```

## Provisioned Resource Inventory

### AWS Resources

| Resource | Purpose | Owner File |
|---|---|---|
| PBM S3 bucket | Stores MongoDB backup archives | `reusable/main.tf` |
| PBM bucket controls (versioning, encryption, public block) | Baseline security | `reusable/main.tf` |
| MongoDB PBM IAM role | Assumed by workload SA for S3/KMS | `reusable/main.tf` |
| MongoDB PBM IAM inline policy | Grants S3 + optional KMS access | `reusable/main.tf` |
| EKS Pod Identity association | Binds SA to IAM role | `reusable/main.tf` |
| Terraform state S3 bucket | Stores Terraform state | `bootstrap-terraform-s3-backend.sh` |
| Aurora PostgreSQL subnet group | Places Aurora in private subnets | `postgresql/main.tf` |
| Aurora PostgreSQL security group | Controls network access | `postgresql/main.tf` |
| Aurora PostgreSQL cluster | Dev database cluster | `postgresql/main.tf` |
| Aurora PostgreSQL writer instance | Single provisioned writer | `postgresql/main.tf` |

### Kubernetes Resources

| Resource | Purpose | Owner File |
|---|---|---|
| `mongodb` namespace | Workload boundary | `reusable/main.tf` |
| MongoDB workload ServiceAccount | IAM identity for pods | `reusable/main.tf` |
| `psmdb-encryption-key` secret | MongoDB encryption key | `bootstrap-dev-secrets.sh` |
| `psmdb-secrets` secret | Operator user credentials | `bootstrap-dev-secrets.sh` |
| Percona HelmRepository + HelmRelease | Operator delivery | `gitops/operators/base/` |
| SigNoz namespace + HelmRepository + HelmRelease | Telemetry delivery | `gitops/signoz/base/` |
| StorageClass `gp3-mongodb` | EBS gp3 storage with WaitForFirstConsumer | `k8s/base/` |
| MongoDB certificates + issuer | TLS for replica set | `k8s/base/certificates.yaml` |
| PerconaServerMongoDB CR | MongoDB replica set definition | `k8s/base/` + `k8s/overlays/dev/` |
| PodDisruptionBudget | Availability during disruption | `k8s/base/pdb.yaml` |
| Kyverno policies | Storage class, sidecar, secret guardrails | `policies/kyverno/` |

### Local-Only Files

| File | Purpose |
|---|---|
| `platform-prerequisites/terraform/mongodb/tfplan` | MongoDB scope plan artifact |
| `platform-prerequisites/terraform/postgresql/tfplan` | PostgreSQL scope plan artifact |
| `.local-dev-encryption-key.txt` | Encryption key escrow |
| `.local-dev-user-passwords.txt` | User credentials escrow |
| `/tmp/mongodb-dev.yaml` | Rendered dev overlay for validation |

## Repository Structure

| Path | Role |
|---|---|
| `platform-prerequisites/terraform/reusable` | Shared module: MongoDB prerequisites |
| `platform-prerequisites/terraform/mongodb` | MongoDB runnable root |
| `platform-prerequisites/terraform/postgresql` | PostgreSQL runnable root |
| `k8s/base/` | Base Kubernetes manifests |
| `k8s/overlays/dev/` | Dev overlay patches |
| `gitops/operators/base/` | Percona Operator HelmRelease |
| `gitops/signoz/base/` | SigNoz HelmRelease |
| `policies/kyverno/` | Admission policies |
| `scripts/` | All operational scripts |
| `docs/` | Documentation hub |

## Script Contracts

| Script | Inputs | Exit Behavior |
|---|---|---|
| `bootstrap-terraform-s3-backend.sh` | `--tf-dir`, `--bucket`, `--region`, `--key` | Non-zero on AWS/TF failures |
| `provision-platform-prereq.sh` | Scope, optional `--auto-approve`, `TF_STATE_*` env | Non-zero on any TF step failure |
| `provision-k8s-components.sh` | Scope, optional `--bootstrap-platform-controllers` | Non-zero on kubectl failures |
| `provision.sh` | Scope, optional flags | Non-zero if any step fails |
| `bootstrap-dev-secrets.sh` | kubectl access to `mongodb` ns | Non-zero on RBAC/tool/creation failure |
| `validate-dev-render.sh` | `kustomize` + `rg` | Non-zero on render/check failure |
| `verify-dev-identity.sh` | Optional: namespace, SA name | 0=ok, 1=no pods, 2=SA mismatch |
| `verify-platform-health.sh` | Optional: `--preflight` | Non-zero if any check fails |

## Script Execution Flows

### bootstrap-terraform-s3-backend.sh

```mermaid
flowchart TD
  A[Parse args + preflight] --> B[Ensure backend s3 block exists]
  B --> C{S3 bucket exists?}
  C -->|No| D[Create bucket + controls]
  C -->|Yes| E[Keep existing]
  D --> F{Remote state object exists?}
  E --> F
  F -->|Yes| G[init -reconfigure]
  F -->|No remote + local exists| H[init -migrate-state]
  F -->|Neither| I[init -reconfigure fresh]
  G --> J[Success]
  H --> J
  I --> J
```

### bootstrap-dev-secrets.sh

```mermaid
flowchart TD
  A[Preflight kubectl RBAC] --> B{Encryption secret exists?}
  B -->|Yes| C[Skip]
  B -->|No| D{Escrow file exists?}
  D -->|Yes| E[Validate + create secret]
  D -->|No| F[Generate + save escrow + create]
  C --> G{Users secret exists?}
  E --> G
  F --> G
  G -->|Yes| H[Skip]
  G -->|No| I{Users escrow exists?}
  I -->|Yes| J[Validate keys + create]
  I -->|No| K[Generate all + save + create]
  H --> L[Done]
  J --> L
  K --> L
```

### provision-platform-prereq.sh

```mermaid
flowchart TD
  A[Select scope + root] --> B[Bootstrap S3 backend]
  B --> C[terraform fmt -recursive]
  C --> D[terraform validate]
  D --> E[terraform plan -out=tfplan]
  E --> F{auto-approve?}
  F -->|Yes| G[terraform apply tfplan]
  F -->|No| H[Show plan + confirm]
  H --> G
```

## Configuration Reference

| File | Owns | Typical Changes |
|---|---|---|
| `reusable/variables.tf` | Shared module defaults | Baseline defaults |
| `reusable/main.tf` | Resources and IAM/S3/K8s wiring | Architecture changes |
| `mongodb/variables.tf` | MongoDB root inputs | Region/cluster/IAM/SA |
| `mongodb/main.tf` | Root execution + module call | Provider/backend |
| `postgresql/variables.tf` | PostgreSQL root inputs | Region/network/sizing |
| `postgresql/main.tf` | Aurora resources | Resource topology |
| `*.tfvars.sample` | Operator templates | Sample values |

Full catalog: [Configuration Catalog](../operations/dev-configuration-catalog.md)

## Day-2 Maintenance

### Routine Workflow
- Rerun `bash scripts/provision-platform-prereq.sh <scope>` after code/default changes
- Review plan output before apply
- Keep `terraform.tfvars.sample` aligned with variable contracts
- Validate MongoDB render and secrets before workload deployment

### Change Flow

```mermaid
flowchart TD
  A[Propose change] --> B[Update Terraform/manifests]
  B --> C[Update docs + config catalog]
  C --> D[Run provisioning]
  D --> E[Review plan]
  E --> F{Approved?}
  F -->|No| B
  F -->|Yes| G[Apply]
  G --> H[Run verification]
  H --> I[Record in docs]
```

### Upgrade Procedures

| Component | How to Upgrade |
|---|---|
| Percona Operator | Update chart version in `gitops/operators/base/helmreleases.yaml`, Flux reconciles |
| SigNoz | Update chart version in `gitops/signoz/base/helmreleases.yaml`, Flux reconciles |
| EBS CSI Driver | `aws eks update-addon --addon-name aws-ebs-csi-driver --addon-version <new>` |
| Terraform providers | Update version constraints in root `versions.tf` |
| MongoDB replica set | Update image/version in PerconaServerMongoDB CR, operator handles rolling upgrade |

### Maintenance Checklist
- Verify provider versions remain compatible
- Review IAM policy scope when integrations change
- Check certificate expiry dates: [Verification Commands § cert-manager](../references/verification-commands.md#cert-manager)
- Confirm backup bucket is receiving objects
- Keep documentation synchronized with behavior changes
