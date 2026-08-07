# ArgoCD IAM Cross-Account Access

Terraform module for creating IAM roles that allow Production ArgoCD to manage Kubernetes clusters across multiple AWS accounts (UAT, DEV, SIT).

## Architecture

**Security Principle**: Production → Non-Production access only (never reverse)

```
Production Account (632674123947)
└─ argocd-cluster-manager-prod
   ├─ Attached to ArgoCD ServiceAccount (IRSA)
   ├─ Manages: Production EKS cluster (local)
   └─ AssumeRole permissions to:
      ├─ arn:aws:iam::672172129937:role/argocd-target-uat
      ├─ arn:aws:iam::815402439714:role/argocd-target-dev
      └─ arn:aws:iam::<SIT-ACCOUNT>:role/argocd-target-sit

UAT/DEV/SIT Accounts
└─ argocd-target-{env}
   ├─ Trust policy: Allows Production argocd-cluster-manager-prod
   ├─ External ID: argocd-prod-to-{env} (security)
   └─ Permissions: eks:DescribeCluster, eks:ListClusters
```

## Deployment Order

**IMPORTANT**: Deploy in this order to avoid circular dependencies:

1. **UAT account** (672172129937): Deploy `argocd-target-uat` role first
2. **DEV account** (815402439714): Deploy `argocd-target-dev` role
3. **SIT account** (TBD): Deploy `argocd-target-sit` role (when SIT is ready)
4. **Production account** (632674123947): Deploy `argocd-cluster-manager-prod` role last (depends on target roles existing)

## Usage

### Step 1: Deploy Target Roles (UAT/DEV/SIT)

```bash
# UAT account
export AWS_PROFILE=AdministratorAccess-672172129937
cd platform-prerequisites/terraform/argocd-iam

terraform init \
  -backend-config="bucket=sml-oms-uat-tfstate" \
  -backend-config="key=argocd-iam/uat.tfstate" \
  -backend-config="region=ap-east-1"

terraform apply \
  -var="environment=uat" \
  -var="cluster_name=oms-uat-eks-cluster" \
  -var="oidc_provider_arn=<UAT_OIDC_ARN>" \
  -var="aws_region=ap-east-1"

# DEV account
export AWS_PROFILE=AdministratorAccess-815402439714
terraform init \
  -backend-config="bucket=sml-oms-dev-tfstate" \
  -backend-config="key=argocd-iam/dev.tfstate" \
  -backend-config="region=ap-east-1"

terraform apply \
  -var="environment=dev" \
  -var="cluster_name=oms-dev-eks-cluster" \
  -var="oidc_provider_arn=<DEV_OIDC_ARN>" \
  -var="aws_region=ap-east-1"
```

### Step 2: Deploy Production Cluster Manager Role

**NOTE**: You mentioned you might not have sufficient privileges to apply in Production. If this fails, work with your admin team to apply this configuration.

```bash
# Production account
export AWS_PROFILE=AdministratorAccess-632674123947
cd platform-prerequisites/terraform/argocd-iam

terraform init \
  -backend-config="bucket=sml-oms-prod-tfstate" \
  -backend-config="key=argocd-iam/prod.tfstate" \
  -backend-config="region=ap-east-1"

terraform apply \
  -var="environment=prod" \
  -var="cluster_name=oms-prod-eks-cluster" \
  -var="oidc_provider_arn=<PROD_OIDC_ARN>" \
  -var="aws_region=ap-east-1"
```

### Step 3: Annotate ArgoCD ServiceAccount (Production only)

After the Production role is created, annotate the ArgoCD ServiceAccount to use IRSA:

```bash
export AWS_PROFILE=AdministratorAccess-632674123947
kubectl --context oms-prod-eks-cluster annotate serviceaccount argocd-application-controller \
  -n argocd \
  eks.amazonaws.com/role-arn=arn:aws:iam::632674123947:role/argocd-cluster-manager-prod
```

### Step 4: Register Remote Clusters

```bash
# Get target account credentials
export AWS_PROFILE=AdministratorAccess-672172129937
aws eks update-kubeconfig --name oms-uat-eks-cluster --region ap-east-1 --alias uat-cluster

# Register with ArgoCD (from Production cluster context)
argocd cluster add uat-cluster \
  --name uat \
  --label env=uat \
  --label account=672172129937

# Repeat for DEV/SIT
```

## Variables

| Variable | Description | Default | Required |
|---|---|---|---|
| `environment` | Environment name (dev, uat, prod, sit) | - | Yes |
| `aws_region` | AWS region | `ap-east-1` | No |
| `cluster_name` | EKS cluster name | - | Yes |
| `oidc_provider_arn` | EKS OIDC provider ARN for IRSA | - | Yes |
| `prod_account_id` | Production account ID | `632674123947` | No |
| `uat_account_id` | UAT account ID | `672172129937` | No |
| `dev_account_id` | DEV account ID | `815402439714` | No |
| `sit_account_id` | SIT account ID | `""` (empty) | No |

## Outputs

### Production Environment
- `argocd_cluster_manager_role_arn`: ARN of the cluster manager role
- `argocd_cluster_manager_role_name`: Name of the cluster manager role
- `k8s_serviceaccount_annotation`: Annotation for ArgoCD ServiceAccount

### Non-Production Environments
- `argocd_target_role_arn`: ARN of the target role
- `argocd_target_role_name`: Name of the target role
- `external_id`: External ID for AssumeRole security

## Security

### External IDs
Each cross-account assume role uses an external ID to prevent confused deputy attacks:
- UAT: `argocd-prod-to-uat`
- DEV: `argocd-prod-to-dev`
- SIT: `argocd-prod-to-sit`

### Least Privilege
Target roles only have `eks:DescribeCluster` and `eks:ListClusters` permissions. Actual Kubernetes RBAC is managed separately via ClusterRoleBinding in each target cluster.

### IRSA (IAM Roles for Service Accounts)
Production ArgoCD uses IRSA to assume the cluster manager role. This is more secure than long-lived credentials.

## Troubleshooting

### Permission Denied
If you get permission denied when applying in Production, verify you have:
- IAM permission to create roles: `iam:CreateRole`, `iam:PutRolePolicy`
- Your AWS CLI profile is set correctly: `echo $AWS_PROFILE`

### Cross-Account AssumeRole Fails
1. Verify target roles exist in UAT/DEV/SIT accounts:
   ```bash
   aws iam get-role --role-name argocd-target-uat --profile AdministratorAccess-672172129937
   ```
2. Check trust policy allows Production role:
   ```bash
   aws iam get-role --role-name argocd-target-uat --query 'Role.AssumeRolePolicyDocument' --profile AdministratorAccess-672172129937
   ```
3. Verify external ID is correct when ArgoCD tries to assume role

### ArgoCD Cannot Access Remote Cluster
1. Check ArgoCD ServiceAccount has the annotation:
   ```bash
   kubectl -n argocd get serviceaccount argocd-application-controller -o yaml | grep eks.amazonaws.com/role-arn
   ```
2. Verify IRSA is working:
   ```bash
   kubectl -n argocd exec -it deployment/argocd-application-controller -- env | grep AWS_ROLE_ARN
   ```
3. Test AssumeRole from ArgoCD pod:
   ```bash
   kubectl -n argocd exec -it deployment/argocd-application-controller -- \
     aws sts assume-role \
       --role-arn arn:aws:iam::672172129937:role/argocd-target-uat \
       --role-session-name test \
       --external-id argocd-prod-to-uat
   ```

## References

- [ArgoCD Multi-Cluster Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters)
- [AWS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Issue #82: ArgoCD Integration](https://github.com/sml-global/mongodb/issues/82)
- Related pattern: `platform-prerequisites/terraform/boomi-elt-s3/` (cross-account S3 access)
