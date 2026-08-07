output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Production outputs
output "argocd_cluster_manager_role_arn" {
  description = "ARN of the Production ArgoCD cluster manager role"
  value       = local.is_prod ? aws_iam_role.argocd_cluster_manager[0].arn : null
}

output "argocd_cluster_manager_role_name" {
  description = "Name of the Production ArgoCD cluster manager role"
  value       = local.is_prod ? aws_iam_role.argocd_cluster_manager[0].name : null
}

# Non-production outputs
output "argocd_target_role_arn" {
  description = "ARN of the target account ArgoCD role (for UAT/DEV/SIT)"
  value       = local.is_prod ? null : aws_iam_role.argocd_target[0].arn
}

output "argocd_target_role_name" {
  description = "Name of the target account ArgoCD role (for UAT/DEV/SIT)"
  value       = local.is_prod ? null : aws_iam_role.argocd_target[0].name
}

output "external_id" {
  description = "External ID for cross-account assume role (security)"
  value       = local.is_prod ? null : "argocd-prod-to-${var.environment}"
}

# Kubernetes ServiceAccount annotation (for IRSA setup)
output "k8s_serviceaccount_annotation" {
  description = "Annotation to add to ArgoCD ServiceAccount for IRSA"
  value = local.is_prod ? {
    "eks.amazonaws.com/role-arn" = aws_iam_role.argocd_cluster_manager[0].arn
  } : null
}
