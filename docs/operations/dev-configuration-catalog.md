# Dev Configuration Catalog

## Purpose
This catalog is the source of truth for embedded configuration in this repository.

- Scope: MongoDB dev workflow files in YAML, Terraform, and shell scripts.
- Goal: make every editable setting discoverable and explicit.

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
- `spec.backup.storages.s3-main.s3.bucket = sml-oms-mongodb-backup-dev`
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
File: `platform-prerequisites/terraform/variables.tf`

- `mongodb_namespace` default: `mongodb`
- `mongodb_workload_service_account_name` default: `psmdb-db`
- `pbm_bucket_name` default: `sml-oms-mongodb-backup-dev`
- `iam_role_name` default: `mongodb-pbm-role`
- `use_pod_identity` default: `true`
- optional empty defaults:
  - `oidc_provider_arn`
  - `oidc_provider_url`
  - `kms_key_arn`

### Dev Wrapper Defaults
File: `platform-prerequisites/terraform/examples/dev/variables.tf`

- `aws_region` default: `us-east-1`
- `mongodb_namespace` default: `mongodb`
- `mongodb_workload_service_account_name` default: `psmdb-db`
- `pbm_bucket_name` default: `sml-oms-mongodb-backup-dev`
- `iam_role_name` default: `mongodb-pbm-role`
- `use_pod_identity` default: `true`

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
  - `platform-prerequisites/terraform/examples/dev`

### ServiceAccount Verification Helper
File: `scripts/verify-dev-identity.sh`

- default namespace arg: `mongodb`
- default expected ServiceAccount arg: `psmdb-db`

## Placeholder Inventory
- MongoDB dev path: no unresolved placeholders in tracked YAML/TF/SH files.
- PostgreSQL dev example intentionally includes a placeholder in:
  - `platform-prerequisites/terraform/examples/dev-postgresql/terraform.tfvars.example`
  - `db_master_password = CHANGE_ME_STRONG_DEV_PASSWORD`
  - this is expected and must be set locally by operator before apply.