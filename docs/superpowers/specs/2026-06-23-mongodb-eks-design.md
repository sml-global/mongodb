# MongoDB on EKS Design (Free-Tool, Production Hardened)

## Document Status
This is a historical design document for the MongoDB EKS bootstrap work.

Current operator workflow, workstation setup, Terraform state behavior, and troubleshooting are maintained in `platform-prerequisites/terraform/README.md`. Current embedded configuration inventory is maintained in `docs/operations/dev-configuration-catalog.md`.

## Scope
- Deploy MongoDB to the existing EKS cluster with current phase scoped to Dev only.
- Use only free/open-source tooling for Kubernetes control plane integrations.
- Keep workload manifests fully declarative (YAML/Helm/Kustomize/GitOps).
- Do not mutate tracked workload manifests at runtime. Current dev-only helper scripts may create missing cluster secrets directly, as documented in the Terraform README and configuration catalog.

## Non-Negotiable Constraints
- Use a MongoDB operator (Percona Operator for MongoDB).
- Percona Backup for MongoDB (PBM) is the authoritative logical restore path for cluster recovery.
- Infrastructure snapshots are compliance artifacts, not authoritative multi-node logical restore inputs.
- Application authentication must use X.509 certificates.
- cert-manager owns application and intra-cluster TLS material issuance.
- External Secrets Operator (ESO) is limited to infrastructure bootstrap secrets only.
- EBS StorageClass must use WaitForFirstConsumer with default gp3 baseline performance.
- Multi-AZ topology spread and anti-affinity are mandatory.
- Sidecar resource fencing for PBM is mandatory.
- All controls must be declarative and GitOps-compatible.

## Architecture Overview
### Control Plane Components
- Flux HelmRelease objects install:
  - cert-manager
  - external-secrets
  - percona-server-mongodb-operator
- Kyverno policies enforce platform and security invariants.

### Data Plane Components
- PerconaServerMongoDB CR defines the replica set, TLS posture, backup profile, and scheduling.
- cert-manager issuers/certificates provide X.509 identities.
- PBM sidecar handles logical backup and restore operations.

### Secret Authority Boundaries
- cert-manager:
  - MongoDB member-to-member TLS
  - client-to-database X.509 certificates
- ESO:
  - bootstrap admin credentials
  - PBM S3 credentials
  - KMS/Vault bootstrap material
- Application namespaces must not consume username/password MongoDB auth from ESO.

### Environment Model
- dev:
  - native Kubernetes Secrets for bootstrap material
  - reduced resources and retention windows
  - no scheduled backups and PITR disabled for cost control while preserving topology parity

## Dev Overlay Configuration
- The dev MongoDB patch is static and tracked in git (`k8s/overlays/dev/patch-psmdb.yaml`).
- PBM bucket and AWS region are deterministic in dev and must match Terraform defaults.
- Validation remains local and read-only: render checks must not mutate manifests.

## Configuration Governance
- Embedded configuration in YAML, Terraform, and shell scripts must be documented in `docs/operations/dev-configuration-catalog.md`.
- Tracked MongoDB dev manifests must not contain unresolved placeholders.
- If a placeholder/token is introduced in the future, the repo must include a resolving script and documentation for how operators populate it.

## Reliability and Recovery
- Replica set size 3 distributed across AZs.
- PDB prevents quorum loss from voluntary disruptions.
- WaitForFirstConsumer avoids cross-AZ EBS pre-binding failures.
- PBM PITR stream is the sole logical restore authority.
- Restore survivability budget must satisfy:
  - RTO = transfer + replay + attach
  - oplog retention must exceed worst-case replay horizon.

## Security
- Require TLS for all MongoDB traffic.
- Require X.509 client auth for application identities.
- Enforce encryption at rest configuration in database engine path.
- Enforce least privilege for ESO and backup identity.

## GitOps and Policy
- Declarative workload apply only.
- No runtime mutation of tracked workload manifests.
- CI runs policy dry-runs using the same policy set as runtime admission.
- Admission controllers remain final guardrails.

## Out of Scope
- Provisioning EKS cluster itself.
- Provisioning cross-account AWS IAM and Pod Identity associations.
- Application-level connection-string rollout across service repos.
- UAT/Prod overlays are deferred to a later phase after Dev stabilization.
