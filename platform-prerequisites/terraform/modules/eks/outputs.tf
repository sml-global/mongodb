output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA bundle used by EKS clients."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL used for IAM role trust configuration."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "node_group_name" {
  description = "Primary managed node group name."
  value       = aws_eks_node_group.primary.node_group_name
}

output "enabled_addon_versions" {
  description = "Explicit addon versions enabled in the cluster."
  value = {
    for name, addon in aws_eks_addon.managed :
    name => addon.addon_version
  }
}