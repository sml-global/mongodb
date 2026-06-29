# MongoDB on EKS (Declarative, Free-Tool Stack)

This repository supports dev provisioning for both:
- MongoDB on EKS (primary workload path in this repo)
- PostgreSQL on Aurora PostgreSQL (dev path under Terraform)

MongoDB deployment model in this repo:
- Flux HelmRelease for tenant-scoped operator installation
- Percona Operator for MongoDB for database lifecycle
- Percona Backup for MongoDB (PBM) for authoritative logical backup and restore
- cert-manager for X.509 auth and TLS
- Kyverno for policy enforcement
- Kustomize overlay for dev

## Guardrails
- No imperative scripts for workload manifest mutation.
- Operator CRDs control database topology and lifecycle.
- PBM logical restore is the only authoritative multi-node restore path.
- Infrastructure snapshots are compliance/forensics artifacts, not replica-set restore authority.
- EFS is not allowed for MongoDB data volumes; this repository uses EBS-backed storage.

## Configuration Catalog
- Complete YAML/TF/SH configuration inventory is maintained in:
  - `docs/operations/dev-configuration-catalog.md`
- Update that catalog whenever embedded configuration is added or changed.

## Folder Layout
- `gitops/operators/base`: tenant-scoped Percona operator installation via Flux HelmRelease
- `k8s/base`: shared MongoDB and platform resources
- `k8s/overlays/dev`: dev settings and native bootstrap secrets
- `policies/kyverno`: policy-as-code guardrails

## Secret Authority Boundaries
- cert-manager authority:
  - member-to-member TLS certificates
  - app client X.509 certificate issuance
- Dev bootstrap secret (`psmdb-encryption-key`) is managed by `scripts/bootstrap-dev-secrets.sh` and created directly in-cluster.

## Prerequisites
- Existing multi-AZ EKS cluster
- Flux controllers installed (`source-controller`, `helm-controller`, `kustomize-controller`)
- `mongodb` namespace provisioned by platform infrastructure (either existing or via Terraform roots in `platform-prerequisites/terraform/dev`)
- `mongodb` namespace contains required ServiceAccounts before apply:
  - `psmdb-db` (or your configured workload ServiceAccount) with AWS Pod Identity/IRSA for backup and encryption integrations
  - `default` (or app-specific ServiceAccounts) with only required least-privilege access
- cert-manager installed cluster-wide
- Kyverno installed cluster-wide if policy enforcement from this repo will be applied
- EKS Pod Identity configured for tenant workloads as needed
- AWS EBS CSI driver available with support for `ebs.csi.aws.com`
- node-local-dns enabled at platform layer
- Platform prerequisites are provided as Terraform under `platform-prerequisites/terraform`.
  - Reusable layer path: `platform-prerequisites/terraform/reusable`.
  - Use unified root at `platform-prerequisites/terraform/dev` for MongoDB + PostgreSQL.
- Confirm Kubernetes context and namespace access before bootstrap/apply:
  - `kubectl config current-context`
  - `kubectl get serviceaccount default -n mongodb`
- Run the dev secret bootstrap script before manifest apply/build:
  - `scripts/bootstrap-dev-secrets.sh`
  - The script only creates missing secrets and reuses local escrow files when present.

## Dev Overlay Configuration
- The dev patch is static and tracked in git at `k8s/overlays/dev/patch-psmdb.yaml`.
- Backup bucket and region are intentionally hardcoded for deterministic dev behavior:
  - bucket: `sml-aw-gb0-d-oms-gen-s3-01`
  - region: `us-east-1`
- No unresolved placeholders are permitted in tracked MongoDB dev manifests.

## Apply Order (GitOps)
1. Provision platform prerequisites for MongoDB + PostgreSQL (`platform-prerequisites/terraform/dev`):
   - `scripts/run-platform-prereq.sh`
   - `(cd platform-prerequisites/terraform/dev && terraform apply tfplan)`
2. Bootstrap dev secret state: `scripts/bootstrap-dev-secrets.sh`.
3. Apply `gitops/operators/base`.
4. Apply `policies/kyverno`.
5. Apply the dev overlay: `k8s/overlays/dev`.

Operator onboarding and script internals are documented in:
- `platform-prerequisites/terraform/README.md`
  - `Read This First`
  - `Standard Operator Procedure`
  - `Required Safety Gates`
  - `Remote State Behavior`
  - `Script Execution Flows`

## Connecting to the Database
- Username: `clusterAdmin`
- Retrieve the bootstrap password:
  - `kubectl get secret psmdb-secrets -n mongodb -o jsonpath='{.data.MONGODB_CLUSTER_ADMIN_PASSWORD}' | base64 --decode`
- Use this username/password with MongoDB Compass or application connection settings.

## Secret Handling (No Git Leakage)
- You do not type a password into README commands. The bootstrap script handles key material automatically.
- If cluster secret `psmdb-encryption-key` already exists, the script skips creation.
- If cluster secret `psmdb-secrets` already exists, the script skips creation.
- If cluster secret is missing and local escrow file exists, the script reuses local escrow key.
- If admin secret is missing and local escrow password exists, the script reuses it.
- If escrow files are missing, the script generates:
  - encryption key via `openssl rand -base64 32`
  - admin password via `openssl rand -base64 24`
- Generated key is saved only to local file `.local-dev-encryption-key.txt` with mode `600`.
- Generated admin password is saved only to local file `.local-dev-admin-password.txt` with mode `600`.
- `.local-dev-encryption-key.txt` is added to `.gitignore` automatically and is never committed.
- `.local-dev-admin-password.txt` is added to `.gitignore` automatically and is never committed.
- Key is sent to Kubernetes through stdin (`--from-file=encryptionKey=/dev/stdin`), so it is not exposed as a CLI argument.

## Secret Recovery Warning
- This repository uses retained EBS volumes.
- If old encrypted data volumes remain but both Kubernetes secret and local escrow key are lost, old data cannot be decrypted.
- For disposable dev data, delete orphaned volumes and bootstrap fresh state.

## Notes on Encryption at Rest
The base CR references `psmdb-encryption-key` for database engine encryption bootstrap material. If your platform standard requires AWS KMS or Vault-backed key management, replace the base encryption configuration with your approved Percona-at-rest encryption backend and keep the same secret authority boundaries.

## Platform Boundary
- This repository does not install cluster-wide cert-manager, Kyverno, or namespaces.
- This repository assumes those platform services already exist where required.
- This repository keeps a MongoDB-specific StorageClass manifest to avoid accidental fallback to a cluster default such as EFS.

## ADR: Percona Over Bitnami
- Decision: Use Percona Operator for MongoDB instead of Bitnami MongoDB chart.
- Status: Accepted.
- Context: This platform requires declarative day-2 operations, PITR-backed restores, and Kubernetes-native lifecycle management in multi-AZ EKS.
- Why Percona:
  - Operator control loop for lifecycle operations on top of MongoDB consensus behavior.
  - Native PBM integration for logical backups and point-in-time recovery.
  - Better fit for CRD-driven GitOps operations where backup/restore and upgrades are first-class.
- Why not Bitnami for this repo:
  - Primarily chart-templated deployment path with less integrated operator-level day-2 control for this target architecture.
  - Would require additional custom operational glue to match PITR and lifecycle expectations already modeled here.
- Consequences:
  - Dev keeps replica-set topology parity (3 members).
  - Dev cost is reduced by lower resource requests and disabled scheduled backups, not by changing topology.

## Validation
Use local repeatable scripts for validation. CI/CD is intentionally not part of this repository scope.

## Repeatable Scripts and Command Recording
- Operational commands are provided in `scripts/` and should be used instead of ad-hoc one-offs.
- For platform bootstrap (MongoDB + PostgreSQL), use `scripts/run-platform-prereq.sh`.
- For secret bootstrap, use `scripts/bootstrap-dev-secrets.sh`.
- For manifest render checks, use `scripts/validate-dev-render.sh`.

## Terraform Merge Strategy
- `platform-prerequisites/terraform/reusable` is the reusable Terraform layer (no provider/backend blocks).
- `platform-prerequisites/terraform/dev` is the local execution root for manual-first deployment.
- After dev validation, merge the module into your main Terraform project and discard the wrapper.

## Execution Tracking
- Current execution snapshot: `docs/operations/execution-status-2026-06-23.md`.
- This snapshot records implemented scope, pending decisions, and missing execution steps before further changes.
