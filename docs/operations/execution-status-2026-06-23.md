# Execution Status - 2026-06-23

## Purpose
This file records what has been implemented, what remains open, and which items require explicit agreement before further code changes.

## Completed
- Repository scaffold created for declarative MongoDB deployment on EKS.
- Percona Operator installation retained as tenant-scoped HelmRelease.
- Cluster-wide platform components (cert-manager, ESO, Kyverno) removed from app-level installation path.
- Namespace manifests removed from app-level deployment path.
- MongoDB-specific EBS StorageClass retained with WaitForFirstConsumer.
- Dev overlay kept at 3-member replica set topology.
- Dev overlay backup subsystem enabled with scheduled backup tasks disabled.
- Dev overlay explicitly disables PITR (`backup.pitr.enabled: false`) to avoid continuous oplog upload costs.
- Dev overlay now uses static deterministic backup storage values (bucket/region).
- Terraform platform prerequisites added under `platform-prerequisites/terraform` (reusable layer at `platform-prerequisites/terraform/reusable`).
- Repeatable scripts added under `scripts/`.
- Scripted validation and operational helpers are present under `scripts/`.
- Workload ServiceAccount (`psmdb-db`) is explicitly set in the dev overlay to keep pod identity mapping deterministic.
- Terraform README now documents EKS API authorization requirement for the runner identity.
- Terraform was refactored into a pure module (`platform-prerequisites/terraform/reusable`) plus manual runnable root (`platform-prerequisites/terraform/dev`).
- Dev hardcoded MongoDB user/password bootstrap secret was removed; operator can generate internal user credentials.
- Dev bootstrap secrets now include both:
  - `psmdb-encryption-key` (encryption key)
  - `psmdb-secrets` (`MONGODB_CLUSTER_ADMIN_PASSWORD`)
- Credential chain conflict was resolved by removing static dev S3 credential secret and removing `credentialsSecret` from PBM storage config.
- Obsolete non-dev `psmdb-backup-s3` ExternalSecret resources were removed as dead code.
- StorageClass already explicitly includes `allowVolumeExpansion: true`.
- Dev bootstrap generates encryption key via `openssl rand -base64 32` and admin password via `openssl rand -base64 24` when missing.
- Memory QoS was hardened to Guaranteed policy by pinning `requests.memory == limits.memory` for MongoDB containers in base/dev.
- PBM sidecar memory in base uses pinned request/limit values to avoid Burstable QoS eviction behavior.
- cert-manager PKI manifests are explicitly present in `k8s/base/certificates.yaml` and included by `k8s/base/kustomization.yaml`.

## In-Progress / Needs Agreement Before Change
1. Manual-first execution boundary:
  - Current state: CI/CD is intentionally out of scope for this repository.
  - Open question: exact handoff point and branch strategy for merging this Terraform into the central platform Terraform repo.

2. Runtime identity proof in target dev cluster:
  - Current state: manifest-level SA wiring is explicit.
  - Open question: run and record post-deploy verification that pods actually run with `psmdb-db` and can reach S3/KMS with current IAM policy scope.

3. Terraform runtime validation in your environment:
  - Current state: structure is ready for manual wrapper execution.
  - Open question: run `scripts/run-platform-prereq.sh` from an authorized IAM identity with EKS API access entry and record outcome.

## Missing Items In Plan (Operational)
- Environment value replacement:
  - MongoDB dev path no longer uses runtime value replacement.
  - Static values must remain aligned between Terraform defaults and dev overlay YAML.
- Runtime validation in target cluster:
  - Verify MongoDB pods run with expected ServiceAccount.
  - Verify PBM sidecar can authenticate to S3/KMS with workload identity.
  - Verify dev overlay deploys in `mongodb` namespace with pre-created platform prerequisites.
- Terraform runtime validation:
  - Local validation currently blocked by local tfenv configuration.
  - Must be validated in an authorized runtime environment.

## Verification Evidence So Far
- Dev manifest render confirms:
  - 3-member replica set
  - backup disabled in dev
  - PITR disabled in dev
  - no static PBM credentials secret reference
  - memory request/limit pinning for Guaranteed QoS in current overlays
  - static dev backup storage bucket/region present
- Evidence has been validated through local render checks and script-based execution.

## Next Step Gate
No additional architectural behavior changes should be made until manual-first runtime validation is executed and recorded.
