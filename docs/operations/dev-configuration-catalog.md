# Dev Configuration Catalog

## Purpose
This catalog is the source of truth for embedded configuration in this repository.

Use this file to answer: "Where is this value defined?".
Use [platform-prerequisites/terraform/README.md](../../platform-prerequisites/terraform/README.md) to answer: "What should I run next?".

## Read This First

| Question | Answer |
|---|---|
| What does this catalog cover? | Embedded dev configuration in Kubernetes YAML, Terraform, and shell scripts. |
| Why does it exist? | To make editable values discoverable without reading every file first. |
| When should it change? | Whenever a tracked default, hardcoded value, script constant, or local operator template changes. |
| Where is operator sequencing documented? | [platform-prerequisites/terraform/README.md](../../platform-prerequisites/terraform/README.md). |
| Who should use it? | Operators, maintainers, and reviewers checking configuration drift. |

Scope: OMS data-layer dev configuration — MongoDB (audit trail), PostgreSQL (primary app database), and SigNoz (application telemetry) across Kubernetes YAML, Terraform, and shell scripts.

Process and operator workflow references:
- [platform-prerequisites/terraform/README.md](../../platform-prerequisites/terraform/README.md):
  - `Workstation Setup`
  - `Provisioned Resource Inventory`
  - `Read This First`
  - `Standard Operator Procedure`
  - `Required Safety Gates`
  - `Remote State Behavior`
  - `Common Problems For New Operators`
  - `Troubleshooting`
  - `Script Execution Flows`

Boundary note:
- This catalog explains configuration inventory only.
- Operator sequencing, gates, and script control flow are maintained in [platform-prerequisites/terraform/README.md](../../platform-prerequisites/terraform/README.md).

## Scope-To-Root Quick Map

| Scope | Terraform Root | Default State Key |
|---|---|---|
| `all` | Runs `mongodb` then `pg` sequentially | Two separate keys (see below) |
| `mongodb` | `platform-prerequisites/terraform/mongodb` | `oms/dev/mongo.tfstate` |
| `pg` | `platform-prerequisites/terraform/postgresql` | `oms/dev/pg.tfstate` |

Use this map when validating whether a setting is in the correct root.

## Configuration Policy
- Tracked workload manifests are static for dev. No runtime manifest mutation is used.
- No unresolved placeholders are allowed in tracked MongoDB dev manifests.
- If a future placeholder/token is introduced, it must include both:
  - a dedicated script that resolves it, and
  - documentation in this catalog and in README.
- Secret values are not committed to git. They are generated or read from local escrow files and applied to cluster secrets by script.

## How Developers Should Change Values
- YAML runtime behavior: edit tracked YAML directly.
- Terraform infrastructure defaults: edit variable defaults in Terraform variable files.
- Local secret material: use bootstrap script only; do not hand-edit secret payloads into YAML.

Review rule:
- If you change a default in YAML/TF/SH, update this catalog in the same change.

## Kubernetes YAML Configuration

### Dev Overlay
File: `k8s/overlays/dev/patch-psmdb.yaml`

- `spec.replsets[0].size = 3`
- `spec.replsets[0].serviceAccountName = psmdb-db`
- `spec.replsets[0].resources.requests.cpu = 250m`
- `spec.replsets[0].resources.requests.memory = 1Gi`
- `spec.replsets[0].resources.limits.cpu = 250m`
- `spec.replsets[0].resources.limits.memory = 1Gi`
- `spec.replsets[0].configuration.storage.wiredTiger.engineConfig.cacheSizeGB = 0.5`
- `spec.replsets[0].volumeSpec.persistentVolumeClaim.storageClassName = gp3-mongodb`
- `spec.replsets[0].volumeSpec.persistentVolumeClaim.resources.requests.storage = 20Gi`
- `spec.backup.enabled = false`
- `spec.backup.pitr.enabled = false`
- `spec.backup.storages.s3-main.s3.bucket = sml-aw-gb0-d-oms-gen-s3-01`
- `spec.backup.storages.s3-main.s3.region = ap-east-1`

Change method: manual YAML edit in git.

### Base Cluster Defaults
File: `k8s/base/psmdb-cluster.yaml`

- operator image/version and cluster defaults
- base replica set resources and storage
- backup schedule defaults and PITR defaults
- secret references:
  - `secrets.users = psmdb-secrets`
  - `secrets.encryptionKey = psmdb-encryption-key`

Change method: manual YAML edit in git.

### StorageClass and Certificate Defaults
Files:
- `k8s/base/storageclass-gp3-mongodb.yaml`
- `k8s/base/certificates.yaml`

Change method: manual YAML edit in git.

### SigNoz Telemetry Base
Files:
- `gitops/signoz/base/namespace.yaml`
- `gitops/signoz/base/helmrepositories.yaml`
- `gitops/signoz/base/helmreleases.yaml`

Defaults:
- namespace: `signoz`
- HelmRepository URL: `https://charts.signoz.io`
- HelmRelease chart: `signoz`
- edition: open-source
- profile: dev all-in-one
- dev access mode: internal-only (no ingress/load balancer manifest in this repo)
- production recommendation: ingress controller (ALB/NGINX) with SSO/OIDC and restricted source networks

Change method: manual YAML edit in git.

## Terraform Configuration

### Reusable Module Defaults
File: `platform-prerequisites/terraform/reusable/variables.tf`

- `mongodb_namespace` default: `mongodb`
- `mongodb_workload_service_account_name` default: `psmdb-db`
- `pbm_bucket_name` default: `sml-aw-gb0-d-oms-gen-s3-01`
- `iam_role_name` default: `mongodb-pbm-role`
- `use_pod_identity` default: `true`
- optional empty defaults:
  - `oidc_provider_arn`
  - `oidc_provider_url`
  - `kms_key_arn`

### MongoDB-Only Root Defaults
File: `platform-prerequisites/terraform/mongodb/variables.tf`

- `aws_region` default: `ap-east-1`
- `mongodb_namespace` default: `mongodb`
- `mongodb_workload_service_account_name` default: `psmdb-db`
- `pbm_bucket_name` default: `sml-aw-gb0-d-oms-gen-s3-01`
- `iam_role_name` default: `mongodb-pbm-role`
- `use_pod_identity` default: `true`

### PostgreSQL-Only Root Defaults
File: `platform-prerequisites/terraform/postgresql/variables.tf`

- `aws_region` default: `ap-east-1`
- `name_prefix` default: `dev-pg18`
- `db_identifier` default: `pg18-dev`
- `instance_class` default: `db.t4g.medium`

## Shell Script Configuration

### Secret Bootstrap
File: `scripts/bootstrap-dev-secrets.sh`

- Namespace: `mongodb`
- Encryption secret name: `psmdb-encryption-key`
- Users secret name: `psmdb-secrets`
- Users secret keys:
  - `MONGODB_BACKUP_USER` / `MONGODB_BACKUP_PASSWORD`
  - `MONGODB_CLUSTER_ADMIN_USER` / `MONGODB_CLUSTER_ADMIN_PASSWORD`
  - `MONGODB_CLUSTER_MONITOR_USER` / `MONGODB_CLUSTER_MONITOR_PASSWORD`
  - `MONGODB_USER_ADMIN_USER` / `MONGODB_USER_ADMIN_PASSWORD`
- Local escrow files:
  - `.local-dev-encryption-key.txt`
  - `.local-dev-user-passwords.txt`
- Behavior:
  - if secret already exists in cluster: skip entirely (no overwrite, no error)
  - if `.local-dev-user-passwords.txt` exists on disk: read credentials from it and create secret
  - if `.local-dev-user-passwords.txt` does not exist: auto-generate all passwords (32-char base64 via `openssl rand -base64 24`), save to escrow file, then create secret
  - same logic applies independently to the encryption key and its escrow `.local-dev-encryption-key.txt`

Change method: manual shell constant edit in git.

### Local Render Validation
File: `scripts/validate-dev-render.sh`

- output path: `/tmp/mongodb-dev.yaml`
- behavior: local render and structural checks only (offline)

### Provision Entry Scripts
Files:
- `scripts/provision.sh`
- `scripts/provision-platform-prereq.sh`
- `scripts/provision-k8s-components.sh`

Defaults and scopes:
- `scripts/provision.sh` scopes:
  - `all`
  - `mongodb`
  - `pg`
  - `signoz`
- `scripts/provision-platform-prereq.sh` scopes:
  - `all`
  - `mongodb`
  - `pg`
- `scripts/provision-k8s-components.sh` scopes:
  - `mongodb`
  - `signoz`
  - `operators`
  - `policies`
  - `overlay`
  - `all`

Change method: manual shell script edit in git.

### Terraform S3 Backend Bootstrap
File: `scripts/bootstrap-terraform-s3-backend.sh`

- Validates required commands (`aws`, `terraform`, `rg`).
- Creates backend S3 bucket if missing.
- Applies baseline controls to newly created bucket:
  - versioning enabled
  - AES256 default encryption
  - public-access block
- Migrates local state to S3 only when remote state does not exist and local state exists.
- Uses existing remote state without re-migration when state object already exists.

### ServiceAccount Verification Helper
File: `scripts/verify-dev-identity.sh`

- default namespace arg: `mongodb`
- default expected ServiceAccount arg: `psmdb-db`

### SigNoz UI Helper
File: `scripts/open-signoz-ui.sh`

- default mode: `port-forward`
- ingress mode available: `--mode ingress`
- default namespace: `signoz`
- port-forward defaults: service `signoz`, local/remote ports `3301:8080`
- ingress defaults: ingress name `signoz`

### Audit Log + Telemetry Helper
File: `scripts/write-auditlog-and-telemetry.sh`

- defaults:
  - Mongo URI: `mongodb://127.0.0.1:27017/?directConnection=true`
  - db/collection: `oms_audit.auditlogs`
  - OTLP endpoint: `http://127.0.0.1:3301/v1/logs`
  - service name: `oms-audit-simulator`
- behavior:
  - shell wrapper delegates to Groovy runtime script: `scripts/write-auditlog-and-telemetry.groovy`
  - test harness exercises Boomi library: `scripts/groovy/boomi/BoomiAuditLogLibrary.groovy`
  - resolves Mongo URI in this order: CLI arg, Kubernetes Secret, AWS Secrets Manager, local default
  - inserts one sample audit-log document directly with Mongo Java driver
  - sends one matching OTLP log record to SigNoz endpoint
  - **cleans up test data** from MongoDB after successful run

## Placeholder Inventory
- MongoDB dev path: no unresolved placeholders in tracked YAML/TF/SH files.
- PostgreSQL dev path intentionally includes a placeholder in:
  - `platform-prerequisites/terraform/postgresql/terraform.tfvars.sample`
  - `db_master_password = CHANGE_ME_STRONG_DEV_PASSWORD`
  - this is expected and must be set locally by operator before apply.

## PostgreSQL Path Configuration
- Aurora PostgreSQL dev defaults and sizing live in:
  - `platform-prerequisites/terraform/postgresql/variables.tf`
- Aurora PostgreSQL dev infrastructure resources live in:
  - `platform-prerequisites/terraform/postgresql/main.tf`
- Aurora PostgreSQL dev outputs live in:
  - `platform-prerequisites/terraform/postgresql/outputs.tf`