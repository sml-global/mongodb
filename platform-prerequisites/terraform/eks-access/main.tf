locals {
  principals = {
    infra_admin           = var.infra_admin_role_arn
    application_developer = var.application_developer_role_arn
    boomi_admin           = var.boomi_admin_role_arn
  }
}

resource "aws_eks_access_entry" "workforce" {
  for_each = local.principals

  cluster_name  = var.eks_cluster_name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_admin" {
  for_each = toset([
    "infra_admin",
    "application_developer",
  ])

  cluster_name  = var.eks_cluster_name
  principal_arn = aws_eks_access_entry.workforce[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_policy_association" "boomi_admin" {
  cluster_name  = var.eks_cluster_name
  principal_arn = aws_eks_access_entry.workforce["boomi_admin"].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.boomi_namespace]
  }
}