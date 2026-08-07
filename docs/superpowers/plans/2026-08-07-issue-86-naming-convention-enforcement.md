# Issue #86: Enforce Namespace Naming Convention Across All Infrastructure

**Date:** 2026-08-07  
**Owner:** Infrastructure Architecture  
**Status:** Planning  
**Issue:** https://github.com/sml-global/mongodb/issues/86

---

## Problem Statement

Naming convention is defined in `docs/UAT-ARCHITECTURE-ISSUES-NAMESPACE-LOGGING.md` § Issue 1, but **not consistently enforced** across the codebase.

**Approved convention:**
```
# Application workloads (MUST include environment suffix)
mongodb-{env}
signoz-{env}
boomi-{env}
test-audit-{env}

# Platform services (NO environment suffix - shared infrastructure)
cert-manager
kyverno
flux-system
kube-system
```

**Rationale:**
- ✅ **Multi-tenancy ready** — if we ever co-locate dev+uat in same cluster
- ✅ **Visual clarity** — `kubectl get pods -A` immediately shows environment
- ✅ **RBAC/network policies** — easier to write rules like "all `-uat` namespaces share X"
- ✅ **Prevents accidents** — harder to run dev script against UAT by mistake
- ✅ **Consistent with GitOps best practices** (ArgoCD, Flux recommend environment in namespace)

---

## Current State Audit

### Phase 1: Discover All Violations

**Known violations:**
- ✅ `signoz` namespace (should be `signoz-uat` in UAT, `signoz-dev` in DEV)
- ✅ `test-audit` namespace (should be `test-audit-uat` or deleted)

**Unknown / not yet audited:**
- ❓ EKS cluster names (e.g., `oms-uat-eks-cluster` vs `EKS-boomi-runtime-cluster`)
- ❓ VPC names (e.g., `oms-uat-vpc`)
- ❓ IAM role names (e.g., `sml-elt-admin-prod` vs `oms-uat-mongodb-backup`)
- ❓ S3 bucket names (e.g., `sml-oms-terraform-state` vs `sml-elt-uat`)
- ❓ RDS Aurora cluster names (e.g., `oms-uat-aurora`)
- ❓ ServiceAccount names in Kubernetes
- ❓ Helm release names
- ❓ Terraform resource names (aws_vpc.main, aws_eks_cluster.main, etc.)

**Action:** Run comprehensive audit script to find all resources and check naming

---

## Discovery Plan

### Step 1: Audit Kubernetes Resources

**Script:** `scripts/audit-naming-convention.sh`

```bash
#!/usr/bin/env bash
# Audit all Kubernetes resources for naming convention violations

ENVIRONMENTS="dev uat"

for ENV in $ENVIRONMENTS; do
  echo "=== Auditing $ENV environment ==="
  
  # Get cluster context
  CLUSTER="oms-${ENV}-eks-cluster"
  
  # Audit namespaces
  kubectl get namespaces -o name --context "$CLUSTER" | while read ns; do
    NAME=$(basename "$ns")
    
    # Skip kube-* namespaces (Kubernetes built-in)
    if [[ "$NAME" == kube-* ]]; then
      continue
    fi
    
    # Check platform services (should NOT have env suffix)
    if [[ "$NAME" =~ ^(cert-manager|kyverno|flux-system)$ ]]; then
      echo "✅ Platform service: $NAME (correct - no suffix)"
      continue
    fi
    
    # Check application workloads (MUST have env suffix)
    if [[ "$NAME" =~ -${ENV}$ ]]; then
      echo "✅ Application workload: $NAME (correct - has -${ENV} suffix)"
    else
      echo "❌ VIOLATION: $NAME (should be ${NAME}-${ENV})"
    fi
  done
  
  # Audit ServiceAccounts
  kubectl get serviceaccounts -A -o json --context "$CLUSTER" | \
    jq -r '.items[] | select(.metadata.namespace != "kube-system") | "\(.metadata.namespace)/\(.metadata.name)"'
  
  # Audit Helm releases
  helm list -A --kube-context "$CLUSTER"
done
```

### Step 2: Audit Terraform Resources

**Files to check:**
- `platform-prerequisites/terraform/*/main.tf`
- `platform-prerequisites/terraform/*/variables.tf`

**Resources to audit:**
- EKS cluster names (`aws_eks_cluster`)
- VPC names (`aws_vpc`)
- IAM role names (`aws_iam_role`)
- S3 bucket names (`aws_s3_bucket`)
- RDS cluster names (`aws_rds_cluster`)
- Security group names (`aws_security_group`)
- Subnet names (`aws_subnet`)

**Expected naming pattern:**
```
oms-{env}-{component}
sml-{component}-{env}  (legacy pattern, may exist)
```

### Step 3: Audit GitOps Manifests

**Files to check:**
- `k8s/*/kustomization.yaml`
- `gitops/*/overlays/*/kustomization.yaml`

**Check for:**
- `namespace:` field in kustomization
- `metadata.namespace` in raw YAML
- HelmRelease `spec.targetNamespace`

### Step 4: Audit Scripts

**Files to check:**
- `scripts/provision*.sh`
- `scripts/destroy*.sh`
- `scripts/verify*.sh`
- `scripts/create-*.sh`
- `scripts/bootstrap-*.sh`

**Check for:**
- Hardcoded namespace names (`-n mongodb`, `-n signoz`)
- Namespace variables (`NAMESPACE=`, `NS=`)
- kubectl commands with namespace flags

---

## Remediation Plan

### Phase 1: Document the Standard (Low Risk)

**Goal:** Make convention explicit and discoverable

**Actions:**
1. ✅ Convention already documented in `docs/UAT-ARCHITECTURE-ISSUES-NAMESPACE-LOGGING.md`
2. Add to `docs/references/component-catalog.md` § "Naming Convention"
3. Add to `docs/guides/architect-reference.md` § "Design Principles"
4. Add to `CLAUDE.md` § "Working Conventions"

**Deliverable:** PR with documentation updates

---

### Phase 2: Fix Kubernetes Namespace Violations (Medium Risk)

**Goal:** Rename non-compliant namespaces

**Known violations:**
1. `signoz` → `signoz-uat` (UAT environment)
2. `signoz` → `signoz-dev` (DEV environment)
3. `test-audit` → `test-audit-uat` or DELETE

**Procedure (per namespace):**

```bash
# Example: Rename signoz → signoz-uat in UAT

# Step 1: Backup current state
kubectl get all -n signoz -o yaml > signoz-backup.yaml

# Step 2: Update GitOps manifests
# Edit gitops/signoz/overlays/uat/kustomization.yaml
# Change: namespace: signoz → namespace: signoz-uat

# Step 3: Create new namespace
kubectl create namespace signoz-uat

# Step 4: Migrate resources (NO DOWNTIME approach)
# - Deploy to new namespace first
# - Verify health
# - Delete old namespace

# Step 5: Update scripts
# - scripts/provision-signoz-observability.sh
# - scripts/create-signoz-*.sh
# - Any verification scripts

# Step 6: Update documentation
# - docs/references/component-catalog.md
# - docs/references/verification-commands.md
```

**Risk mitigation:**
- ✅ Provision new namespace first (zero-downtime)
- ✅ Run health checks before deleting old namespace
- ✅ Keep backup YAML for rollback
- ✅ Test in DEV before UAT

**Deliverable:** PR per namespace rename

---

### Phase 3: Fix Terraform Resource Names (High Risk - Breaking Change)

**Goal:** Rename Terraform resources to follow convention

**Known potential violations:**
- EKS cluster: `EKS-boomi-runtime-cluster` → `oms-dev-eks-cluster` (DEV)
- S3 buckets: Various patterns → `sml-oms-{component}-{env}`

**IMPORTANT:** Renaming Terraform resources = destroy + recreate (DESTRUCTIVE)

**Options:**
1. **Option A: Terraform state move** (non-destructive)
   ```bash
   terraform state mv aws_eks_cluster.main aws_eks_cluster.oms_dev
   # Update code to use new resource name
   ```
   - ✅ No resource recreation
   - ❌ State file churn
   - ❌ Must update all references

2. **Option B: Aliases + deprecation** (gradual migration)
   ```hcl
   # Keep old name, add alias
   resource "aws_eks_cluster" "main" {
     name = "oms-dev-eks-cluster"
     # ... (new naming convention)
   }
   
   # Alias for backwards compatibility
   output "legacy_cluster_name" {
     value = "EKS-boomi-runtime-cluster"
     description = "DEPRECATED: Use oms-dev-eks-cluster"
   }
   ```
   - ✅ Gradual migration
   - ✅ No immediate breakage
   - ❌ Dual naming persists

3. **Option C: Accept legacy names** (document exception)
   - ✅ No risk
   - ❌ Inconsistency remains
   - Document as "legacy pattern, do not repeat"

**Recommendation:** Option C for EKS clusters (too risky to rename), Option A for new resources

**Deliverable:** Decision document + PR if renaming approved

---

### Phase 4: Add CI Validation (Low Risk)

**Goal:** Prevent future violations

**Actions:**
1. **Pre-commit hook:** `scripts/hooks/validate-naming-convention.sh`
   ```bash
   #!/usr/bin/env bash
   # Validate all namespace declarations follow convention
   
   VIOLATIONS=$(grep -r "namespace:" k8s gitops | \
     grep -v "cert-manager\|kyverno\|flux-system\|kube-system" | \
     grep -v -- "-dev\|-uat\|-prod\|-sit")
   
   if [ -n "$VIOLATIONS" ]; then
     echo "❌ Namespace naming violations found:"
     echo "$VIOLATIONS"
     exit 1
   fi
   ```

2. **GitHub Actions:** `.github/workflows/validate-naming.yml`
   - Run on every PR
   - Block merge if violations found

3. **Kustomize build test:** Validate all overlays build without error

**Deliverable:** PR with CI validation

---

## Execution Plan

### Timeline

**Week 1 (Aug 7-13):**
- ✅ Create issue #86
- ✅ Create this plan
- Run discovery audit (Step 1-4)
- Document findings

**Week 2 (Aug 14-20):**
- Phase 1: Documentation updates (PR)
- Phase 2: Fix signoz namespace in DEV (PR + test)
- Phase 2: Fix signoz namespace in UAT (PR + deploy)

**Week 3 (Aug 21-27):**
- Phase 3: Decision on Terraform resource renaming
- Phase 3: Execute approved renames (if any)
- Phase 4: Add CI validation

**Week 4 (Aug 28+):**
- Final audit
- Close issue #86

### Dependencies

- ❌ **UAT-only operations rule** — can only test in UAT (DEV off-limits per CLAUDE.md)
- ✅ **No production impact** — Production not yet provisioned

---

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|---|---|---|---|
| Namespace rename breaks GitOps | HIGH | LOW | Deploy to new namespace first, verify health before deleting old |
| Scripts hardcode old namespace names | MEDIUM | MEDIUM | Grep all scripts, update references, test in DEV first |
| Terraform rename destroys resources | CRITICAL | MEDIUM | Use `terraform state mv` (non-destructive) OR accept legacy names |
| CI validation blocks legitimate work | LOW | LOW | Whitelist exceptions (kube-*, platform services) |

---

## Success Criteria

- [ ] Convention documented in ≥3 places (current: 1)
- [ ] All application namespaces have environment suffix
- [ ] All platform namespaces have NO environment suffix
- [ ] CI validation prevents future violations
- [ ] Zero production incidents during migration
- [ ] Issue #86 closed

---

## Open Questions

1. **EKS cluster naming:** Rename `EKS-boomi-runtime-cluster` → `oms-dev-eks-cluster`?
   - **Risk:** High (would require cluster recreation or complex state move)
   - **Recommendation:** Document as legacy exception, use correct naming for UAT/Prod

2. **S3 bucket naming:** Unify to `sml-oms-{component}-{env}` pattern?
   - **Risk:** Medium (bucket rename = recreate, can preserve via state move)
   - **Recommendation:** New buckets use convention, legacy buckets documented

3. **IAM role naming:** Current mix of `sml-*` and `oms-*` prefixes?
   - **Risk:** Low (roles rarely referenced by name in code)
   - **Recommendation:** New roles use `oms-{env}-{component}`, document exceptions

4. **Terraform resource names:** Rename `main` → `oms_{env}_{component}`?
   - **Risk:** Low (internal to Terraform state)
   - **Recommendation:** Future refactors only, not worth risk now

---

## Related Documents

- **Convention source:** `docs/UAT-ARCHITECTURE-ISSUES-NAMESPACE-LOGGING.md` § Issue 1
- **Component catalog:** `docs/references/component-catalog.md`
- **Architect reference:** `docs/guides/architect-reference.md`
- **Issue tracker:** https://github.com/sml-global/mongodb/issues/86
