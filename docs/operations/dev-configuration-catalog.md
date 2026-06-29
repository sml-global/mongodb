# Dev Configuration Catalog

## Purpose
This catalog is the source of truth for embedded configuration in this repository.

- Scope: unified MongoDB + PostgreSQL dev workflow files in YAML, Terraform, and shell scripts.
- Goal: make every editable setting discoverable and explicit.

Process and operator workflow references:
- `platform-prerequisites/terraform/README.md`:
  - `Read This First`
  - `Standard Operator Procedure`
  - `Required Safety Gates`
  - `Remote State Behavior`
  - `Script Execution Flows`

Boundary note:
- This catalog explains configuration inventory only.
- Operator sequencing, gates, and script control flow are maintained in the Terraform README.

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
- `spec.backup.storages.s3-main.s3.region = us-east-1`

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

### MongoDB Root Defaults
File: `platform-prerequisites/terraform/dev/variables.tf`

- `aws_region` default: `us-east-1`
- `mongodb_namespace` default: `mongodb`
- `mongodb_workload_service_account_name` default: `psmdb-db`
- `pbm_bucket_name` default: `sml-aw-gb0-d-oms-gen-s3-01`
- `iam_role_name` default: `mongodb-pbm-role`
- `use_pod_identity` default: `true`
- PostgreSQL defaults (same root):
  - `name_prefix` default: `dev-pg18`
  - `db_identifier` default: `pg18-dev`
  - `instance_class` default: `db.t4g.medium`

Change method: manual Terraform variable default edit in git, or override in local `terraform.tfvars` for local runs.

## Shell Script Configuration

### Secret Bootstrap
File: `scripts/bootstrap-dev-secrets.sh`

- Namespace: `mongodb`
- Encryption secret name: `psmdb-encryption-key`
- Admin secret name: `psmdb-secrets`
- Local escrow files:
  - `.local-dev-encryption-key.txt`
  - `.local-dev-admin-password.txt`
- Behavior:
  - if secret exists in cluster: skip
  - if missing: generate/use local escrow and create

Change method: manual shell constant edit in git.

### Local Render Validation
File: `scripts/validate-dev-render.sh`

- output path: `/tmp/mongodb-dev.yaml`
- behavior: local render and structural checks only (offline)

### Terraform Wrapper Runner
File: `scripts/run-platform-prereq.sh`

- Terraform working directory fixed to:
  - `platform-prerequisites/terraform/dev`
- Optional remote-state env controls:
  - `TF_STATE_BUCKET`
  - `TF_STATE_REGION` (default `us-east-1`)
  - `TF_STATE_KEY` (default `mongodb/platform-prerequisites/dev/terraform.tfstate`)

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

## Placeholder Inventory
- MongoDB dev path: no unresolved placeholders in tracked YAML/TF/SH files.
- PostgreSQL dev path intentionally includes a placeholder in:
  - `platform-prerequisites/terraform/dev/terraform.tfvars.sample`
  - `db_master_password = CHANGE_ME_STRONG_DEV_PASSWORD`
  - this is expected and must be set locally by operator before apply.

## PostgreSQL Path Configuration
- Aurora PostgreSQL dev defaults and sizing live in:
  - `platform-prerequisites/terraform/dev/variables.tf`
- Aurora PostgreSQL dev infrastructure resources live in:
  - `platform-prerequisites/terraform/dev/main.tf`
- Aurora PostgreSQL dev outputs live in:
  - `platform-prerequisites/terraform/dev/outputs.tf`