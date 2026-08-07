# ArgoCD Multi-Environment Architecture Options

**Question**: Can one single ArgoCD in Production manage all Kubernetes clusters in different environments (DEV, UAT, Production)? Or must we have one ArgoCD per environment?

---

## TL;DR Answer

**Yes, one ArgoCD can manage multiple Kubernetes clusters across environments**, but there are important trade-offs:

- ✅ **Centralized ArgoCD** (1 instance → many clusters) is possible and common
- ✅ **Distributed ArgoCD** (1 instance per environment) is also valid
- 🔧 **Hybrid approach** (central + local) often works best

**Recommendation for OMS**: **Centralized ArgoCD in Production managing all environments** (DEV, UAT, Production, SIT)

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

1. **You already have cross-account patterns** - PR #76 implements cross-account S3 with AssumeRole
2. **Small footprint** - 4 small clusters don't justify 4 ArgoCD instances
3. **Central visibility** - aligns with UAT-only operational policy (central monitoring)
4. **Flux is already present** - transitioning from Flux → ArgoCD is easier with centralized approach

### Implementation Plan

#### Phase 1: Deploy ArgoCD in Production Cluster
```bash
# In Production account
export AWS_PROFILE=AdministratorAccess-632674123947
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

#### Phase 2: Create Cross-Account IAM Roles

**Production account** (632674123947):
```hcl
# Terraform: platform-prerequisites/terraform/argocd-iam/prod.tf
resource "aws_iam_role" "argocd_cluster_manager" {
  name = "argocd-cluster-manager-prod"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::632674123947:oidc-provider/${OIDC_PROVIDER}"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${OIDC_PROVIDER}:sub" = "system:serviceaccount:argocd:argocd-application-controller"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "argocd_assume_target_roles" {
  role = aws_iam_role.argocd_cluster_manager.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Resource = [
        "arn:aws:iam::672172129937:role/argocd-target-uat",
        "arn:aws:iam::815402439714:role/argocd-target-dev",
        # SIT account when created
      ]
    }]
  })
}
```

**UAT account** (672172129937):
```hcl
# Terraform: platform-prerequisites/terraform/argocd-iam/uat.tf
resource "aws_iam_role" "argocd_target" {
  name = "argocd-target-uat"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::632674123947:role/argocd-cluster-manager-prod"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "argocd-prod-to-uat"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "argocd_target_eks" {
  role = aws_iam_role.argocd_target.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ]
      Resource = "*"
    }]
  })
}
```

**Repeat for DEV/SIT accounts**

#### Phase 3: Register Remote Clusters in ArgoCD

```bash
# From Production cluster
export AWS_PROFILE=AdministratorAccess-632674123947

# Assume UAT role
aws sts assume-role \
  --role-arn arn:aws:iam::672172129937:role/argocd-target-uat \
  --role-session-name argocd-register-uat \
  --external-id argocd-prod-to-uat

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

#### Phase 4: Configure RBAC via Identity Center

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

**Production account** (632674123947):
- IAM role: `argocd-cluster-manager-prod` (attached to ArgoCD ServiceAccount)
- Permissions: `sts:AssumeRole` to target account roles

**Target accounts** (UAT/DEV/SIT):
- IAM role: `argocd-target-{env}` (trusted by Production ArgoCD)
- Trust policy: Allows Production `argocd-cluster-manager-prod` with external ID
- Permissions: `eks:DescribeCluster`, `eks:ListClusters`

**External IDs** (security):
- `argocd-prod-to-uat`
- `argocd-prod-to-dev`
- `argocd-prod-to-sit`

### Distributed ArgoCD (Alternative)

**Each account** (DEV/UAT/Production/SIT):
- IAM role: `argocd-local-{env}` (attached to local ArgoCD ServiceAccount)
- Permissions: Local cluster access only (no cross-account)
- Identity Center permission sets:
  - `ArgoCD-Admin-DEV` → account 815402439714
  - `ArgoCD-Admin-UAT` → account 672172129937
  - `ArgoCD-Admin-PROD` → account 632674123947

---

## Next Steps

1. **Decide architecture**: Centralized (recommended) vs. Distributed vs. Hybrid
2. **If centralized**:
   - Create Terraform modules for cross-account IAM roles
   - Deploy ArgoCD in Production cluster (after Production is provisioned)
   - Register UAT cluster first (test with UAT-only policy)
3. **If distributed**:
   - Deploy ArgoCD in UAT cluster (UAT-only policy allows this)
   - Create Identity Center permission sets per environment
   - Test UAT ArgoCD before expanding to other environments

**Recommendation**: Start with **centralized ArgoCD in Production**, test with UAT cluster registration first.
