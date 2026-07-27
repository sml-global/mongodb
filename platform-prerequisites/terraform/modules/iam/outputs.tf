output "cluster_role_arn" {
  description = "IAM role ARN for EKS control plane."
  value       = aws_iam_role.cluster_role.arn
}

output "node_role_arn" {
  description = "IAM role ARN for EKS managed node groups."
  value       = aws_iam_role.node_role.arn
}

output "addon_role_arn" {
  description = "IAM role ARN for CSI managed add-ons."
  value       = aws_iam_role.addon_role.arn
}

output "autoscaler_role_arn" {
  description = "IAM role ARN for autoscaler integrations."
  value       = aws_iam_role.autoscaler_role.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN dedicated to cluster-autoscaler."
  value       = aws_iam_role.cluster_autoscaler_role.arn
}

output "lbc_role_arn" {
  description = "IAM role ARN dedicated to AWS Load Balancer Controller."
  value       = var.enable_load_balancer_controller ? aws_iam_role.lbc_role[0].arn : null
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA-enabled service accounts."
  value       = aws_iam_openid_connect_provider.cluster.arn
}