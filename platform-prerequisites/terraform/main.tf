locals {
  workload_sa_name = var.mongodb_workload_service_account_name
  namespace        = var.mongodb_namespace

  pod_identity_principal = {
    Service = "pods.eks.amazonaws.com"
  }

  irsa_principal = {
    Federated = var.oidc_provider_arn
  }

  role_actions = var.use_pod_identity ? ["sts:AssumeRole", "sts:TagSession"] : ["sts:AssumeRoleWithWebIdentity"]
}

resource "kubernetes_namespace" "mongodb" {
  metadata {
    name = local.namespace
    labels = {
      "app.kubernetes.io/part-of" = "mongodb-platform"
    }
  }
}

resource "aws_s3_bucket" "pbm" {
  bucket = var.pbm_bucket_name
}

resource "aws_s3_bucket_versioning" "pbm" {
  bucket = aws_s3_bucket.pbm.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pbm" {
  bucket = aws_s3_bucket.pbm.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pbm" {
  bucket = aws_s3_bucket.pbm.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = local.role_actions

    dynamic "principals" {
      for_each = var.use_pod_identity ? [1] : []
      content {
        type        = "Service"
        identifiers = [local.pod_identity_principal.Service]
      }
    }

    dynamic "principals" {
      for_each = var.use_pod_identity ? [] : [1]
      content {
        type        = "Federated"
        identifiers = [local.irsa_principal.Federated]
      }
    }

    dynamic "condition" {
      for_each = var.use_pod_identity ? [] : [1]
      content {
        test     = "StringEquals"
        variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
        values   = ["system:serviceaccount:${local.namespace}:${local.workload_sa_name}"]
      }
    }

    dynamic "condition" {
      for_each = var.use_pod_identity ? [] : [1]
      content {
        test     = "StringEquals"
        variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role" "mongodb_pbm" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "mongodb_pbm" {
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      aws_s3_bucket.pbm.arn,
      "${aws_s3_bucket.pbm.arn}/*"
    ]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn == "" ? [] : [1]
    content {
      sid    = "KMSAccess"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "mongodb_pbm" {
  name   = "${var.iam_role_name}-policy"
  role   = aws_iam_role.mongodb_pbm.id
  policy = data.aws_iam_policy_document.mongodb_pbm.json
}

resource "kubernetes_service_account" "mongodb_workload" {
  metadata {
    name      = local.workload_sa_name
    namespace = kubernetes_namespace.mongodb.metadata[0].name
    annotations = var.use_pod_identity ? {} : {
      "eks.amazonaws.com/role-arn" = aws_iam_role.mongodb_pbm.arn
    }
  }
}

resource "aws_eks_pod_identity_association" "mongodb_workload" {
  count = var.use_pod_identity ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = local.namespace
  service_account = kubernetes_service_account.mongodb_workload.metadata[0].name
  role_arn        = aws_iam_role.mongodb_pbm.arn
}