# platform-prerequisites/terraform/dr-drill/main.tf
#
# Least-privilege IAM roles for automated DR restore drills. The MongoDB and
# PostgreSQL roles are READ-ONLY (s3:GetObject/ListBucket only) and MUST NOT
# be reused for production restore operations. The ClickHouse role is
# READ+WRITE but scoped only to its own dedicated backup bucket (Task 3
# creates backups, not just restores them) -- see
# docs/superpowers/specs/2026-07-28-phase4-day2-operations-design.md (D3, D8).

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster's IAM OIDC provider (from the eks-platform root's output)"
  type        = string
}

variable "oidc_provider_url" {
  description = "Issuer URL of the EKS cluster's IAM OIDC provider, e.g. https://oidc.eks.<region>.amazonaws.com/id/<id>"
  type        = string
}

locals {
  oidc_hostpath = replace(var.oidc_provider_url, "https://", "")
}

# --- MongoDB PBM restore drill role (read-only) ---

data "aws_iam_policy_document" "dr_drill_mongodb_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:dr-drill-uat:dr-drill-runner"]
    }
  }
}

data "aws_iam_policy_document" "dr_drill_mongodb_restore" {
  statement {
    sid    = "ReadOnlyPbmBackupAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::oms-pbm-backups",
      "arn:aws:s3:::oms-pbm-backups/*",
    ]
  }
}

resource "aws_iam_role" "dr_drill_mongodb_restore_role" {
  name               = "dr-drill-mongodb-restore-role"
  assume_role_policy = data.aws_iam_policy_document.dr_drill_mongodb_trust.json
}

resource "aws_iam_role_policy" "dr_drill_mongodb_restore" {
  name   = "dr-drill-mongodb-restore-readonly"
  role   = aws_iam_role.dr_drill_mongodb_restore_role.id
  policy = data.aws_iam_policy_document.dr_drill_mongodb_restore.json
}

# --- PostgreSQL WAL/PITR restore drill role (read-only) ---

data "aws_iam_policy_document" "dr_drill_postgresql_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:dr-drill-uat:dr-drill-runner"]
    }
  }
}

data "aws_iam_policy_document" "dr_drill_postgresql_restore" {
  statement {
    sid    = "ReadOnlyWalArchiveAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::oms-postgresql-wal-archive",
      "arn:aws:s3:::oms-postgresql-wal-archive/*",
    ]
  }
}

resource "aws_iam_role" "dr_drill_postgresql_restore_role" {
  name               = "dr-drill-postgresql-restore-role"
  assume_role_policy = data.aws_iam_policy_document.dr_drill_postgresql_trust.json
}

resource "aws_iam_role_policy" "dr_drill_postgresql_restore" {
  name   = "dr-drill-postgresql-restore-readonly"
  role   = aws_iam_role.dr_drill_postgresql_restore_role.id
  policy = data.aws_iam_policy_document.dr_drill_postgresql_restore.json
}

# --- ClickHouse backup+restore drill role (read+write, own bucket ONLY) ---
# Unlike the two roles above, this one also creates backups (Task 3 runs
# `clickhouse-backup create` + `upload`), so it needs s3:PutObject -- but
# strictly scoped to its own dedicated bucket, never oms-pbm-backups or
# oms-postgresql-wal-archive.

data "aws_iam_policy_document" "dr_drill_clickhouse_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:dr-drill-uat:dr-drill-runner"]
    }
  }
}

data "aws_iam_policy_document" "dr_drill_clickhouse_backup" {
  statement {
    sid    = "ClickhouseBackupBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::oms-signoz-clickhouse-backups",
      "arn:aws:s3:::oms-signoz-clickhouse-backups/*",
    ]
  }
}

resource "aws_iam_role" "dr_drill_clickhouse_backup_role" {
  name               = "dr-drill-clickhouse-backup-role"
  assume_role_policy = data.aws_iam_policy_document.dr_drill_clickhouse_trust.json
}

resource "aws_iam_role_policy" "dr_drill_clickhouse_backup" {
  name   = "dr-drill-clickhouse-backup-scoped"
  role   = aws_iam_role.dr_drill_clickhouse_backup_role.id
  policy = data.aws_iam_policy_document.dr_drill_clickhouse_backup.json
}

# NOTE: this repo's convention is Terraform-manages-AWS-only; Kubernetes
# objects are always created via GitOps/kubectl scripts (see
# scripts/create-signoz-root-user-secret.sh), never via the `kubernetes`
# Terraform provider (verified: no other root in this repo defines any
# kubernetes_* resource). The role ARNs are exposed as outputs; a bootstrap
# script (Step 3b below) turns them into the ConfigMap the CronJob reads.

output "dr_drill_mongodb_role_arn" {
  value = aws_iam_role.dr_drill_mongodb_restore_role.arn
}

output "dr_drill_postgresql_role_arn" {
  value = aws_iam_role.dr_drill_postgresql_restore_role.arn
}

output "dr_drill_clickhouse_role_arn" {
  value = aws_iam_role.dr_drill_clickhouse_backup_role.arn
}
