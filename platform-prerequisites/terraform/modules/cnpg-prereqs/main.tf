# Generic namespace + S3 backup bucket + IAM pod-identity role for a
# self-managed CNPG (CloudNativePG) PostgreSQL cluster. Generalized from
# platform-prerequisites/terraform/reusable/main.tf's MongoDB/PBM pattern so
# each CNPG cluster (core, brand, ...) can get its own independent namespace,
# bucket, and role via a separate invocation of this module with its own
# state key, root, backup bucket, IAM role name, and namespace name --
# letting each be provisioned, resized, or destroyed independently.
locals {
  pod_identity_principal = {
    Service = "pods.eks.amazonaws.com"
  }

  irsa_principal = {
    Federated = var.oidc_provider_arn
  }

  role_actions = var.use_pod_identity ? ["sts:AssumeRole", "sts:TagSession"] : ["sts:AssumeRoleWithWebIdentity"]
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/part-of" = "postgresql-platform"
    }
  }
}

resource "aws_s3_bucket" "backup" {
  bucket = var.backup_bucket_name
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

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
        values   = ["system:serviceaccount:${var.namespace}:${var.workload_service_account_name}"]
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

resource "aws_iam_role" "workload" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "workload" {
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
      aws_s3_bucket.backup.arn,
      "${aws_s3_bucket.backup.arn}/*"
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

resource "aws_iam_role_policy" "workload" {
  name   = "${var.iam_role_name}-policy"
  role   = aws_iam_role.workload.id
  policy = data.aws_iam_policy_document.workload.json
}

resource "kubernetes_service_account_v1" "workload" {
  metadata {
    name      = var.workload_service_account_name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    annotations = var.use_pod_identity ? {} : {
      "eks.amazonaws.com/role-arn" = aws_iam_role.workload.arn
    }
  }
}

resource "aws_eks_pod_identity_association" "workload" {
  count = var.use_pod_identity ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = kubernetes_service_account_v1.workload.metadata[0].name
  role_arn        = aws_iam_role.workload.arn
}
