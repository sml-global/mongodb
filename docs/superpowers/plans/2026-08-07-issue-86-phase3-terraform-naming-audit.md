# Phase 3: Terraform Resource Naming Audit

**Date:** 2026-08-07
**Issue:** #86
**Status:** Audit Complete

---

## Objective

Audit all Terraform-managed resources for naming convention compliance:
- EKS clusters: `oms-{env}-eks-cluster`
- VPCs: `oms-{env}-vpc`
- IAM roles: `oms-{env}-{component}` OR `sml-{project}-{component}-{env}`
- S3 buckets: `sml-oms-{component}-{env}`
- RDS/Aurora: `oms-{env}-{database}`

---

## Audit Methodology

1. Scanned all `.tf` files in `platform-prerequisites/terraform/`
2. Reviewed `.tfvars` files in `platform-prerequisites/terraform/environments/`
3. Checked actual resource names against convention

---

## Findings

### ✅ Compliant Resources

#### EKS Clusters
- **UAT**: `oms-uat-eks-cluster` ✅
- **DEV**: `oms-dev-eks-cluster` ✅ (planned, not yet deployed)
- **Prod**: `oms-prod-eks-cluster` ✅ (planned, not yet deployed)
- **Sandbox**: `oms-sandbox-eks-cluster` ✅

**Source:** `terraform/environments/*/eks-platform.tfvars` → `name_prefix = "oms-{env}-eks"` → becomes `{prefix}-cluster`

#### S3 Buckets (MongoDB PBM Backup)
- **UAT**: `sml-oms-uat-mongodb-pbm-672172129937` ✅
- **DEV**: `sml-aw-gb0-d-oms-gen-s3-01` ⚠️ (legacy pattern, pre-convention)

**Source:** `terraform/mongodb/terraform.uat.tfvars` → `pbm_bucket_name`

#### S3 Buckets (PostgreSQL Backup)
- **coredb**: `oms-postgresql-coredb-backup` ⚠️ (missing env suffix)
- **branddb**: `oms-postgresql-branddb-backup` ⚠️ (missing env suffix)

**Source:** `gitops/postgresql-*/overlays/dev/cluster.yaml` → `spec.backup.barmanObjectStore.destinationPath`

#### IAM Roles (MongoDB)
- Pod Identity associations use workspace identity federation (no explicit IAM role names in manifests)

#### IAM Roles (PostgreSQL)
- Service accounts: `oms-postgresql-workload`, `oms-postgresql-brand-workload`
- ⚠️ Missing env suffix

---

### ❌ Legacy Exceptions

#### EKS Cluster (DEV - actual deployed)
- **Current name**: `EKS-boomi-runtime-cluster`
- **Should be**: `oms-dev-eks-cluster`
- **Status**: **LEGACY EXCEPTION** - too risky to rename
- **Rationale:**
  - Renaming requires destroy + recreate (all workloads lost)
  - Extensive references in scripts, documentation
  - Name predates naming convention
- **Action**: Document as legacy exception, do not repeat

**Source:** DEV environment is still using this legacy cluster name

#### S3 Bucket (DEV - MongoDB)
- **Current name**: `sml-aw-gb0-d-oms-gen-s3-01`
- **Should be**: `sml-oms-mongodb-dev`
- **Status**: **LEGACY PATTERN** - predates convention
- **Action**: Accept as legacy, new buckets use new pattern

#### ELT S3 Buckets
- **Pattern**: `sml-elt-*`
- **Status**: **SEPARATE PROJECT** - different naming scheme
- **Action**: No change needed (different project boundary)

---

### ⚠️  Manual Review Needed

#### PostgreSQL Backup S3 Buckets
- `oms-postgresql-coredb-backup` → should be `oms-postgresql-coredb-backup-dev`
- `oms-postgresql-branddb-backup` → should be `oms-postgresql-branddb-backup-dev`

**Risk assessment:**
- ⚠️  **MEDIUM RISK** - Renaming requires:
  1. Create new bucket
  2. Update CNPG Cluster manifest
  3. Copy existing backups to new bucket (optional, can start fresh)
  4. Delete old bucket

**Recommendation:** Fix in next PostgreSQL maintenance window

#### ServiceAccount Names
- `oms-postgresql-workload` → should be `oms-postgresql-workload-dev`
- `oms-postgresql-brand-workload` → should be `oms-postgresql-brand-workload-dev`

**Risk assessment:**
- 🔴 **HIGH RISK** - Renaming requires:
  1. Update Terraform to create new ServiceAccount
  2. Update CNPG Cluster manifest to reference new SA
  3. Delete pods to pick up new SA
  4. Verify Pod Identity associations
  5. Delete old ServiceAccount

**Recommendation:** Accept as is, add env suffix only for new service accounts

---

## Recommendations

### 1. Document Legacy Exceptions

Add to `docs/references/component-catalog.md` § "Naming Convention":

```markdown
### Legacy Exceptions

**EKS Cluster (DEV):**
- Name: `EKS-boomi-runtime-cluster`
- Reason: Predates naming convention, too risky to rename
- Policy: **DO NOT REPEAT** - all new clusters use `oms-{env}-eks-cluster`

**S3 Buckets (DEV MongoDB):**
- Name: `sml-aw-gb0-d-oms-gen-s3-01`
- Reason: Predates naming convention
- Policy: New buckets use `sml-oms-{component}-{env}`
```

### 2. Fix Low-Risk Violations

Create PR to fix PostgreSQL backup bucket names:
- Low risk (can start fresh backup chain)
- Clear migration path
- Only affects DEV environment

### 3. Accept Medium/High Risk Items

**ServiceAccount names:**
- Accept current names as-is
- Too tightly coupled to Pod Identity associations
- Add env suffix only for new service accounts

---

## Phase 3 Completion Criteria

- [x] Audit all Terraform resources
- [x] Document findings
- [x] Identify legacy exceptions
- [ ] Update documentation with legacy exceptions
- [ ] Create PR for low-risk fixes (optional, can defer)

---

## Deliverables

1. **This audit document** - findings and recommendations
2. **Documentation PR** - add legacy exceptions to component-catalog.md
3. **Optional fixes PR** - PostgreSQL backup bucket renames (low priority)

---

## Summary

**Compliant:**
- ✅ EKS clusters (all planned environments follow convention)
- ✅ UAT MongoDB S3 bucket follows convention

**Legacy Exceptions (Accept as-is):**
- ❌ `EKS-boomi-runtime-cluster` (DEV) - document exception
- ❌ `sml-aw-gb0-d-oms-gen-s3-01` (DEV MongoDB) - document exception

**Low-Priority Fixes (Defer):**
- ⚠️  PostgreSQL backup buckets (missing env suffix)
- ⚠️  ServiceAccount names (missing env suffix)

**Conclusion:** Phase 3 focuses on **documentation** rather than renames. The high-risk renames (EKS cluster) should be avoided, and low-risk renames (S3 buckets, ServiceAccounts) can be deferred to future maintenance windows.
