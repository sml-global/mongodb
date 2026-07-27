output "access_entry_arns" {
  value = {
    for principal, entry in aws_eks_access_entry.workforce : principal => entry.access_entry_arn
  }
}

output "associated_policy_arns" {
  value = {
    infra_admin           = aws_eks_access_policy_association.cluster_admin["infra_admin"].policy_arn
    application_developer = aws_eks_access_policy_association.cluster_admin["application_developer"].policy_arn
    boomi_admin           = aws_eks_access_policy_association.boomi_admin.policy_arn
  }
}