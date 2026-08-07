# =============================================================================
# PRODUCTION ENVIRONMENT: ArgoCD Cluster Manager Role
# =============================================================================
# This role is attached to the ArgoCD ServiceAccount in Production cluster
# and allows ArgoCD to assume roles in UAT/DEV/SIT accounts.
#
# Security principle: Production → Non-Production access only (never reverse)
# =============================================================================

resource "aws_iam_role" "argocd_cluster_manager" {
  count = local.is_prod ? 1 : 0
  name  = "argocd-cluster-manager-prod"

  # Trust policy: Allow ArgoCD ServiceAccount to assume this role via IRSA
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_url}:sub" = "system:serviceaccount:${local.argocd_namespace}:${local.argocd_sa_name}"
            "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  max_session_duration = 3600  # 1 hour

  tags = {
    Name        = "ArgoCD Cluster Manager (Production)"
    Description = "Allows Production ArgoCD to manage multiple clusters via cross-account assume roles"
  }
}

# Production ArgoCD permissions: Manage local cluster + assume roles in target accounts
resource "aws_iam_role_policy" "argocd_cluster_manager" {
  count = local.is_prod ? 1 : 0
  name  = "argocd-cluster-manager-policy"
  role  = aws_iam_role.argocd_cluster_manager[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Local EKS cluster access (Production cluster)
      {
        Sid    = "LocalClusterAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${var.prod_account_id}:cluster/${var.cluster_name}"
      },
      # AssumeRole permissions for remote clusters (UAT/DEV/SIT)
      {
        Sid    = "AssumeRoleInTargetAccounts"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = compact([
          "arn:aws:iam::${var.uat_account_id}:role/argocd-target-uat",
          "arn:aws:iam::${var.dev_account_id}:role/argocd-target-dev",
          var.sit_account_id != "" ? "arn:aws:iam::${var.sit_account_id}:role/argocd-target-sit" : null
        ])
      }
    ]
  })
}

# =============================================================================
# NON-PRODUCTION ENVIRONMENTS: ArgoCD Target Role
# =============================================================================
# These roles exist in UAT/DEV/SIT accounts and are assumable by Production ArgoCD.
# They grant ArgoCD permission to access the EKS cluster in that account.
#
# Security: External ID prevents confused deputy attacks
# =============================================================================

resource "aws_iam_role" "argocd_target" {
  count = local.is_prod ? 0 : 1
  name  = "argocd-target-${var.environment}"

  # Trust policy: Allow Production ArgoCD role to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.prod_account_id}:role/argocd-cluster-manager-prod"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "argocd-prod-to-${var.environment}"
          }
        }
      }
    ]
  })

  max_session_duration = 3600  # 1 hour

  tags = {
    Name        = "ArgoCD Target (${upper(var.environment)})"
    Description = "Allows Production ArgoCD to access ${upper(var.environment)} EKS cluster"
  }
}

# Target role permissions: Read-only EKS cluster access
resource "aws_iam_role_policy" "argocd_target" {
  count = local.is_prod ? 0 : 1
  name  = "argocd-target-${var.environment}-policy"
  role  = aws_iam_role.argocd_target[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSClusterAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"  # ArgoCD needs to discover clusters in this account
      }
    ]
  })
}
