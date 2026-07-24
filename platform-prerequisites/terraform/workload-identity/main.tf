data "terraform_remote_state" "eks_platform" {
  backend = "s3"

  config = {
    bucket       = var.eks_platform_state_bucket
    key          = var.eks_platform_state_key
    region       = var.aws_region
    use_lockfile = var.eks_platform_state_use_lockfile
  }
}

locals {
  platform_contract    = data.terraform_remote_state.eks_platform.outputs.platform_contract
  expected_cluster_arn = "arn:aws:eks:${var.aws_region}:${var.expected_account_id}:cluster/${var.cluster_name}"
}

check "platform_contract_identity_match" {
  assert {
    condition     = local.platform_contract.account_id == var.expected_account_id
    error_message = "platform_contract account_id must match expected_account_id."
  }

  assert {
    condition     = local.platform_contract.region == var.aws_region
    error_message = "platform_contract region must match aws_region."
  }

  assert {
    condition     = local.platform_contract.environment == var.environment
    error_message = "platform_contract environment must match environment input."
  }

  assert {
    condition     = local.platform_contract.cluster_name == var.cluster_name
    error_message = "platform_contract cluster_name must match cluster_name input."
  }

  assert {
    condition     = local.platform_contract.cluster_arn == local.expected_cluster_arn
    error_message = "platform_contract cluster_arn must match expected account, region, and cluster identity."
  }
}

data "aws_iam_policy_document" "pod_identity_assume_role" {
  for_each = var.identities

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "identity" {
  for_each = var.identities

  name               = "${var.environment}-${each.key}"
  description        = each.value.description
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role[each.key].json
}

resource "aws_iam_role_policy" "identity" {
  for_each = var.identities

  name   = "${var.environment}-${each.key}-policy"
  role   = aws_iam_role.identity[each.key].id
  policy = each.value.policy_json
}

resource "aws_eks_pod_identity_association" "identity" {
  for_each = var.identities

  cluster_name    = local.platform_contract.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.identity[each.key].arn
}
