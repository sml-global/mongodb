# ArgoCD Multi-Environment Architecture Options

**Question**: Can one single ArgoCD in Production manage all Kubernetes clusters in different environments (DEV, UAT, Production, SIT)? Or must we have one ArgoCD per environment?

**Context**: As of August 2026, OMS operational policy allows **Production and UAT** environments for live operations. DEV and SIT remain restricted for safety.

---

## TL;DR Answer

**Yes, one ArgoCD can manage multiple Kubernetes clusters across environments**, but there are important trade-offs:

- ✅ **Centralized ArgoCD** (1 instance → many clusters) is possible and common
- ✅ **Distributed ArgoCD** (1 instance per environment) is also valid
- 🔧 **Hybrid approach** (central + local) often works best

**Recommendation for OMS**: **Centralized ArgoCD in Production managing all environments** (Production, UAT, DEV, SIT)

**Security Principle**: Access flows **FROM Production TO non-production** (never reverse) — Production credentials never exposed to lower environments.

---

## Architecture Option 1: Centralized ArgoCD (One Instance, Many Clusters)

### Design

```
Production Account (632674123947)
└─ ArgoCD in oms-prod-eks-cluster
   ├─ Manages: oms-prod-eks-cluster (local)
   ├─ Manages: oms-uat-eks-cluster (remote, cross-account)
   ├─ Manages: oms-dev-eks-cluster (remote, cross-account)
   └─ Manages: oms-sit1/2/3-eks-cluster (remote, cross-account)
```

**How it works**:
- ArgoCD server runs in Production cluster
- ArgoCD connects to remote clusters using kubeconfig + IAM credentials
- All environments visible in **one ArgoCD UI**
- Applications (MongoDB, PostgreSQL, SigNoz) deployed to target clusters

### Cross-Account Access (IAM Approach)

**Option A: IAM Roles for Service Accounts (IRSA)** - AWS-native

1. **Production ArgoCD ServiceAccount** gets IAM role
2. **Target account (UAT/DEV/SIT)** creates assumable role:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {
         "AWS": "arn:aws:iam::632674123947:role/argocd-cluster-manager-prod"
       },
       "Action": "sts:AssumeRole",
       "Condition": {
         "StringEquals": {
           "sts:ExternalId": "argocd-prod-to-uat"
         }
       }
     }]
   }
   ```
3. **Trust policy** allows Production ArgoCD role to assume UAT/DEV roles
4. **Permissions in target account**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": [
         "eks:DescribeCluster",
         "eks:ListClusters"
       ],
       "Resource": "*"
     }]
   }
   ```

**Option B: AWS Identity Center (SSO) Permission Sets** - Human + Machine

1. **Create permission set**: `ArgoCD-Cluster-Manager`
   - Policy: `eks:DescribeCluster`, `eks:ListClusters`
   - Kubernetes RBAC: `system:masters` or custom ClusterRole
2. **Assign to ArgoCD service account** (if Identity Center supports machine identities)
3. **Or**: Use Identity Center for human operators, IRSA for ArgoCD pods

**Option C: Cross-Account VPC Peering + Kubernetes RBAC** - Network-level

1. **VPC peering** between Production ↔ UAT/DEV/SIT (managed by Landing Zone team)
2. **ArgoCD connects via private IPs** (no internet exposure)
3. **Kubernetes RBAC** in target clusters:
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: argocd-manager
     namespace: kube-system
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: argocd-manager
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: cluster-admin
   subjects:
   - kind: ServiceAccount
     name: argocd-manager
     namespace: kube-system
   ```
4. **ArgoCD uses ServiceAccount token** from target cluster

### Pros ✅

- **Single pane of glass** - all environments in one UI
- **Consistent policies** - same RBAC, same workflows across all envs
- **Cost-effective** - one ArgoCD instance (smaller footprint)
- **Centralized audit trail** - all deployments logged in one place
- **Easier to maintain** - update ArgoCD once, applies to all clusters
- **Follows security best practice** - Production → Non-Production access direction (never reverse)
- **Same user group** - Team logs in once, all environments visible, RBAC controls per-env permissions

### Cons ❌

- **Single point of failure** - if Production ArgoCD is down, cannot deploy to ANY environment (including DEV)
- **Cross-account IAM complexity** - need trust relationships + assumable roles in each account
- **Blast radius** - misconfiguration in Production ArgoCD could affect all environments
- **Network dependencies** - requires VPC peering or internet-accessible EKS endpoints

### When to Use

- ✅ You want centralized control and visibility
- ✅ You have mature IAM/network setup (Landing Zone team supports cross-account access)
- ✅ Production stability is high (ArgoCD rarely fails)
- ✅ You want to enforce consistent deployment policies across environments

---

## Architecture Option 2: Distributed ArgoCD (One Per Environment)

### Design

```
DEV Account (815402439714)
└─ ArgoCD in oms-dev-eks-cluster
   └─ Manages: oms-dev-eks-cluster (local only)

UAT Account (672172129937)
└─ ArgoCD in oms-uat-eks-cluster
   └─ Manages: oms-uat-eks-cluster (local only)

Production Account (632674123947)
└─ ArgoCD in oms-prod-eks-cluster
   └─ Manages: oms-prod-eks-cluster (local only)

SIT Account (TBD)
└─ ArgoCD in oms-sit1-eks-cluster
   └─ Manages: oms-sit1-eks-cluster (local only)
```

**How it works**:
- Each environment has its own ArgoCD instance
- Each ArgoCD manages **only its local cluster**
- No cross-account IAM complexity
- Operators must log into 4 separate ArgoCD UIs

### IAM Approach (Simpler)

1. **ArgoCD ServiceAccount** in each cluster gets local IAM role (IRSA)
2. **No cross-account trust relationships** needed
3. **Permission set per environment**:
   - `ArgoCD-Admin-DEV` (account 815402439714)
   - `ArgoCD-Admin-UAT` (account 672172129937)
   - `ArgoCD-Admin-PROD` (account 632674123947)
4. **Users assigned to appropriate permission sets** via Identity Center

### Pros ✅

- **Isolated blast radius** - DEV ArgoCD failure doesn't affect UAT/Production
- **No cross-account IAM** - each ArgoCD uses local cluster credentials only
- **Independent upgrade cycles** - upgrade DEV ArgoCD without affecting Production
- **Environment-specific RBAC** - different users/permissions per environment

### Cons ❌

- **Multiple UIs** - operators must log into 4 separate ArgoCD instances
- **Inconsistent policies** - each ArgoCD configured separately (drift risk)
- **Higher cost** - 4 ArgoCD instances = 4× resource footprint
- **Maintenance burden** - update ArgoCD 4 times (once per environment)
- **No cross-environment visibility** - cannot see "what's deployed in all envs" in one view

### When to Use

- ✅ You want isolated failure domains (DEV downtime doesn't affect Production)
- ✅ You have small clusters (ArgoCD resource footprint is acceptable)
- ✅ You want independent upgrade cycles per environment
- ✅ You don't need cross-environment visibility in one UI

---

## Architecture Option 3: Hybrid (Central Production + Local DEV)

### Design

```
Production Account (632674123947)
└─ ArgoCD in oms-prod-eks-cluster
   ├─ Manages: oms-prod-eks-cluster (local)
   ├─ Manages: oms-uat-eks-cluster (remote)
   └─ Manages: oms-sit1/2/3-eks-cluster (remote)

DEV Account (815402439714)
└─ ArgoCD in oms-dev-eks-cluster
   └─ Manages: oms-dev-eks-cluster (local only)
```

**Rationale**:
- **Production ArgoCD** manages production-like environments (UAT, SIT, Production)
- **DEV ArgoCD** is isolated (developers can break it without affecting production path)

### Pros ✅

- **Isolated DEV experimentation** - developers can test ArgoCD changes in DEV
- **Production-path consistency** - UAT/SIT/Production managed by same ArgoCD
- **Lower risk** - DEV failures don't affect production ArgoCD
- **Cost compromise** - only 2 ArgoCD instances instead of 4

### Cons ❌

- **Two UIs** - still need to log into 2 separate ArgoCD instances
- **DEV/Production drift** - DEV ArgoCD may have different configuration

### When to Use

- ✅ DEV is for experimentation (including infrastructure experiments)
- ✅ You want production-path consistency (UAT → Production)
- ✅ You want to protect Production ArgoCD from DEV chaos

---

## Recommendation for OMS: Centralized ArgoCD in Production

**Recommended architecture**: **Option 1 (Centralized)** with **Option A (IRSA cross-account IAM)**

### Why?

1. **Follows security best practice** - Production → Non-Production access direction (never reverse)
2. **You already have cross-account patterns** - `platform-prerequisites/terraform/boomi-elt-s3/` implements cross-account S3 with AssumeRole (PR #76)
3. **Small footprint** - 4 small clusters don't justify 4 ArgoCD instances
4. **Central visibility** - One UI for all environments aligns with operational policy
5. **Single user group** - Team logs in once, sees all 4 environments, RBAC controls per-env permissions
6. **Flux is already present** - Transitioning from Flux → ArgoCD is easier with centralized approach
7. **Production + UAT allowed** - Revised operational policy permits live operations in both environments (DEV/SIT remain restricted)

### Implementation Plan

#### Phase 1: Deploy ArgoCD in Production Cluster

**Prerequisites**:
- Production EKS cluster must exist: `oms-prod-eks-cluster`
- OIDC provider configured for IRSA
- kubectl access to Production cluster

```bash
# In Production account
export AWS_PROFILE=AdministratorAccess-632674123947
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

#### Phase 2: Create Cross-Account IAM Roles

**IMPORTANT**: Terraform modules have been created at `platform-prerequisites/terraform/argocd-iam/`

**Deployment order** (to avoid circular dependencies):
1. Deploy target roles in UAT/DEV/SIT first (so they exist before Production role references them)
2. Deploy Production cluster manager role last

See `platform-prerequisites/terraform/argocd-iam/README.md` for detailed deployment instructions.

#### Phase 3: Annotate ArgoCD ServiceAccount (IRSA)

After deploying the Production IAM role, annotate the ArgoCD ServiceAccount to use it:

```bash
export AWS_PROFILE=AdministratorAccess-632674123947
kubectl --context oms-prod-eks-cluster annotate serviceaccount argocd-application-controller \
  -n argocd \
  eks.amazonaws.com/role-arn=arn:aws:iam::632674123947:role/argocd-cluster-manager-prod
```

#### Phase 4: Register Remote Clusters in ArgoCD

```bash
# From Production cluster
export AWS_PROFILE=AdministratorAccess-632674123947

# Update kubeconfig for UAT cluster
aws eks update-kubeconfig \
  --name oms-uat-eks-cluster \
  --region ap-east-1 \
  --profile AdministratorAccess-672172129937 \
  --alias uat-cluster

# Register cluster with ArgoCD
argocd cluster add uat-cluster \
  --name uat \
  --label env=uat \
  --label account=672172129937

# Repeat for DEV/SIT
```

#### Phase 5: Configure RBAC via Identity Center

**Create permission sets**:

1. **ArgoCD-Admin-Production** (full access)
   - Inline policy: `argocd:*` on all resources
   - Assign to: Production platform team

2. **ArgoCD-Operator-UAT** (read-only + sync)
   - Inline policy: `argocd:Get*`, `argocd:List*`, `argocd:Sync*`
   - Assign to: UAT operators, Boomi admins

3. **ArgoCD-Viewer-All** (read-only)
   - Inline policy: `argocd:Get*`, `argocd:List*`
   - Assign to: Developers, auditors

**Map to Kubernetes RBAC**:
```yaml
# In Production cluster
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-admin
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-admin-sso
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-admin
subjects:
- kind: Group
  name: "ArgoCD-Admin-Production"  # Identity Center group
  apiGroup: rbac.authorization.k8s.io
```

#### Phase 5: SSO Integration (Optional)

ArgoCD supports OIDC via AWS Identity Center:

```yaml
# argocd-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.oms.example.com
  oidc.config: |
    name: AWS SSO
    issuer: https://oidc.ap-east-1.amazonaws.com/id/XXXXXX
    clientID: $OIDC_CLIENT_ID
    clientSecret: $OIDC_CLIENT_SECRET
    requestedScopes: ["openid", "profile", "email"]
```

---

## IAM Summary: Cross-Account Access

### Centralized ArgoCD (Recommended)

**Implementation**: Terraform modules created at `platform-prerequisites/terraform/argocd-iam/`

**Production account** (632674123947):
- IAM role: `argocd-cluster-manager-prod` (attached to ArgoCD ServiceAccount via IRSA)
- Permissions: `sts:AssumeRole` to target account roles + `eks:DescribeCluster` for local cluster

**Target accounts** (UAT/DEV/SIT):
- IAM role: `argocd-target-{env}` (trusted by Production ArgoCD)
- Trust policy: Allows Production `argocd-cluster-manager-prod` with external ID
- Permissions: `eks:DescribeCluster`, `eks:ListClusters`

**External IDs** (security against confused deputy attacks):
- `argocd-prod-to-uat`
- `argocd-prod-to-dev`
- `argocd-prod-to-sit`

**Security Principle Enforced**:
- ✅ Production → Non-Production: Allowed (Production ArgoCD assumes roles in lower environments)
- ❌ Non-Production → Production: Blocked (no trust relationship in reverse direction)

### Distributed ArgoCD (Alternative - Not Recommended)

**Each account** (DEV/UAT/Production/SIT):
- IAM role: `argocd-local-{env}` (attached to local ArgoCD ServiceAccount)
- Permissions: Local cluster access only (no cross-account)
- Identity Center permission sets:
  - `ArgoCD-Admin-DEV` → account 815402439714
  - `ArgoCD-Admin-UAT` → account 672172129937
  - `ArgoCD-Admin-PROD` → account 632674123947

---

## Next Steps

1. **Architecture decided**: ✅ Centralized ArgoCD in Production (recommended)
2. **Terraform modules created**: ✅ `platform-prerequisites/terraform/argocd-iam/`
3. **Next actions**:
   - Deploy target IAM roles in UAT/DEV/SIT accounts (see Terraform module README)
   - Deploy Production cluster manager IAM role (requires Production cluster + OIDC provider)
   - Deploy ArgoCD in Production cluster
   - Register UAT cluster first as test case
   - Expand to DEV/SIT once validated

**Updated Policy**: Both **Production and UAT** environments are now approved for live operations (DEV/SIT remain restricted per safety rules).

**See Also**:
- `platform-prerequisites/terraform/argocd-iam/README.md` - Full deployment instructions
- `platform-prerequisites/terraform/boomi-elt-s3/` - Similar cross-account pattern (PR #76)
- Issue #82 - ArgoCD integration tracking issue
