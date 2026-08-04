locals {
  cluster_oidc_hostpath = replace(var.cluster_oidc_issuer_url, "https://", "")
}

data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = var.cluster_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [var.cluster_oidc_thumbprint]
}

data "aws_iam_policy_document" "service_account_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.cluster_oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.cluster_oidc_hostpath}:sub"
      values = [
        "system:serviceaccount:kube-system:cluster-autoscaler*",
        "system:serviceaccount:kube-system:aws-load-balancer-controller",
        "system:serviceaccount:kube-system:ebs-csi-controller-sa",
        "system:serviceaccount:kube-system:efs-csi-controller-sa",
      ]
    }
  }
}

resource "aws_iam_role" "cluster_role" {
  name               = "${var.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node_role" {
  name               = "${var.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role" "addon_role" {
  name               = "${var.name_prefix}-eks-addon-role"
  assume_role_policy = data.aws_iam_policy_document.service_account_assume.json
}

resource "aws_iam_role_policy_attachment" "addon_ebs_policy" {
  role       = aws_iam_role.addon_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy_attachment" "addon_efs_policy" {
  role       = aws_iam_role.addon_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

resource "aws_iam_role" "autoscaler_role" {
  name               = "${var.name_prefix}-eks-autoscaler-role"
  assume_role_policy = data.aws_iam_policy_document.service_account_assume.json
}

resource "aws_iam_role" "cluster_autoscaler_role" {
  name               = "${var.name_prefix}-eks-cluster-autoscaler-role"
  assume_role_policy = data.aws_iam_policy_document.service_account_assume.json
}

# Standard upstream cluster-autoscaler IAM policy (see
# https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md#IAM-Policy).
# Read actions are unscoped (cluster-autoscaler must discover ASGs across
# the account by tag); mutating actions are restricted to ASGs tagged for
# autoscaler management, so this role can never scale/terminate instances
# in an unrelated ASG.
data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid    = "ClusterAutoscalerRead"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ClusterAutoscalerWrite"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name   = "${var.name_prefix}-eks-cluster-autoscaler-policy"
  role   = aws_iam_role.cluster_autoscaler_role.id
  policy = data.aws_iam_policy_document.cluster_autoscaler.json
}

resource "aws_iam_role" "lbc_role" {
  count              = var.enable_load_balancer_controller ? 1 : 0
  name               = "${var.name_prefix}-eks-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.service_account_assume.json
}

# AWS's own published IAM policy for this exact controller
# (https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json),
# vendored verbatim rather than hand-transcribed to avoid drift/mistakes.
resource "aws_iam_role_policy" "lbc" {
  count  = var.enable_load_balancer_controller ? 1 : 0
  name   = "${var.name_prefix}-eks-lbc-policy"
  role   = aws_iam_role.lbc_role[0].id
  policy = file("${path.module}/aws-load-balancer-controller-policy.json")
}