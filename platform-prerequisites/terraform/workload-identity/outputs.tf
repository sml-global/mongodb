output "identity_associations" {
  description = "Map of workload identity associations keyed by identity ID."
  value = {
    for identity_key, identity in var.identities : identity_key => {
      role_name                   = aws_iam_role.identity[identity_key].name
      role_arn                    = aws_iam_role.identity[identity_key].arn
      namespace                   = identity.namespace
      service_account             = identity.service_account
      pod_identity_association_id = aws_eks_pod_identity_association.identity[identity_key].association_id
    }
  }
}
