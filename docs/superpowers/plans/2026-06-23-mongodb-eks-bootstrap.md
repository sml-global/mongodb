# MongoDB EKS Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a fully declarative repository for Percona MongoDB on EKS with dev overlay and policy guardrails.

**Architecture:** Use Flux HelmRelease for operator installations and Kustomize overlays for environment-specific resources. Percona CRDs define MongoDB runtime; policies enforce storage, secret authority boundaries, and security constraints.

**Tech Stack:** Kubernetes YAML, Kustomize, Flux HelmRelease CRDs, Percona Operator for MongoDB, cert-manager, Kyverno.

---

### Task 1: Scaffold repository layout
**Files:**
- Create: `gitops/operators/base/*`
- Create: `k8s/base/*`
- Create: `k8s/overlays/dev/*`

- [ ] Add kustomization roots for operators and workloads.
- [ ] Add env overlay kustomizations.
- [ ] Add README with apply order.

### Task 2: Add operator installation layer (declarative)
**Files:**
- Create: `gitops/operators/base/namespaces.yaml`
- Create: `gitops/operators/base/helmrepositories.yaml`
- Create: `gitops/operators/base/helmreleases.yaml`

- [ ] Define namespaces for cert-manager, external-secrets, and mongodb.
- [ ] Add HelmRepository resources.
- [ ] Add HelmRelease resources with explicit chart versions.

### Task 3: Add MongoDB base CR and security controls
**Files:**
- Create: `k8s/base/psmdb-cluster.yaml`
- Create: `k8s/base/pdb.yaml`
- Create: `k8s/base/storageclass-gp3-mongodb.yaml`
- Create: `k8s/base/certificates.yaml`
- Create: `k8s/base/kustomization.yaml`

- [ ] Define PerconaServerMongoDB CR with 3-node replica set.
- [ ] Add strict scheduling constraints (anti-affinity + topology spread).
- [ ] Add PBM sidecar CPU/memory requests and limits.
- [ ] Add storage class with WaitForFirstConsumer and gp3 performance params.
- [ ] Add cert-manager issuer/cert resources for mTLS and client auth.

### Task 4: Add environment overlays
**Files:**
- Create: `k8s/overlays/dev/*`

- [ ] Dev overlay uses native K8s bootstrap secrets and smaller resource profile.
- [ ] Repository scope is Dev-only for this phase.

### Task 5: Add policy-as-code guardrails
**Files:**
- Create: `policies/kyverno/*.yaml`
- Create: `policies/kyverno/kustomization.yaml`

- [ ] Add policy enforcing WaitForFirstConsumer for MongoDB storageclass use.
- [ ] Add policy blocking ESO-managed app auth secrets in application namespaces.
- [ ] Add policy requiring PBM sidecar resource limits.

### Task 6: Local validation only
**Files:**
- Use existing scripts under `scripts/`.

- [x] Run `scripts/validate-dev-render.sh`.
- [x] Run validation scripts as part of the local dev workflow.

### Task 7: Dev overlay injection workflow
- [x] Convert the dev Mongo patch into a tracked template.
- [x] Generate the injected overlay from Terraform outputs before render/apply.
- [x] Keep the generated overlay ignored by git.
- [x] Make dev render validation invoke the injector first.

### Task 8: Documentation and usage
**Files:**
- Create: `README.md`

- [ ] Document prerequisites (Pod Identity, IAM roles, AWS Secret Manager entries).
- [ ] Document apply order for GitOps and manual validation steps.
- [ ] Document restore authority boundaries (PBM authoritative, snapshots compliance-only).
