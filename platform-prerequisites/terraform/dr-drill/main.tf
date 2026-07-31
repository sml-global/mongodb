# platform-prerequisites/terraform/dr-drill/main.tf
#
# Least-privilege IAM roles for automated DR restore drills. The MongoDB and
# PostgreSQL roles are READ-ONLY (s3:GetObject/ListBucket only) and MUST NOT
# be reused for production restore operations. The ClickHouse drill role is
# READ+WRITE but scoped only to its own dedicated backup bucket (Task 3
# creates backups, not just restores them) -- see
# docs/superpowers/specs/2026-07-28-phase4-day2-operations-design.md (D3, D8).
#
# All 4 roles below use EKS Pod Identity (not IRSA/OIDC), matching this
# repo's established pattern in ../workload-identity/main.tf -- see D14.

variable "cluster_name" {
  description = "Name of the EKS cluster to associate the dr-drill IAM roles with via EKS Pod Identity."
  type        = string
}

variable "aws_region" {
  description = "AWS region for dr-drill platform resources."
  type        = string
}

variable "expected_account_id" {
  description = "Expected AWS account ID from the platform contract."
  type        = string
}

# Pod Identity trust policy is identical for every role: the EKS Pod Identity
# Agent (Service principal) assumes the role on behalf of a pod, then the
# separate aws_eks_pod_identity_association resource below binds a specific
# role to a specific namespace/ServiceAccount pair -- unlike IRSA, no
# per-ServiceAccount `sub` claim condition is needed in the trust policy
# itself. Mirrors platform-prerequisites/terraform/workload-identity/main.tf.
data "aws_iam_policy_document" "dr_drill_pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# --- MongoDB PBM restore drill role (read-only) ---
# Bound to its OWN dedicated ServiceAccount (dr-drill-mongodb-runner) via the
# aws_eks_pod_identity_association below -- each drill has a separate
# CronJob + ServiceAccount because Pod Identity binds exactly one role per
# ServiceAccount; see k8s/dr-drill/cronjob.yaml header.

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
  assume_role_policy = data.aws_iam_policy_document.dr_drill_pod_identity_trust.json
}

resource "aws_iam_role_policy" "dr_drill_mongodb_restore" {
  name   = "dr-drill-mongodb-restore-readonly"
  role   = aws_iam_role.dr_drill_mongodb_restore_role.id
  policy = data.aws_iam_policy_document.dr_drill_mongodb_restore.json
}

resource "aws_eks_pod_identity_association" "dr_drill_mongodb" {
  cluster_name    = var.cluster_name
  namespace       = "dr-drill-uat"
  service_account = "dr-drill-mongodb-runner"
  role_arn        = aws_iam_role.dr_drill_mongodb_restore_role.arn
}

# The orchestrator pod above (dr-drill-uat) only does the `aws sts
# get-caller-identity` identity guard check -- the actual `pbm restore` S3
# reads happen inside the `pbm-agent` container of the throwaway
# restore-target pod, which runs in its OWN fixed namespace
# (dr-drill-mongodb-restore-target, see scripts/dr-drill-mongodb-restore.sh)
# under the SAME ServiceAccount name. Pod Identity associations require an
# exact static namespace+ServiceAccount match (no wildcards), so this
# fixed, reusable namespace needs its own association -- reusing the same
# least-privilege read-only role above (no new IAM role needed).
resource "aws_eks_pod_identity_association" "dr_drill_mongodb_restore_target" {
  cluster_name    = var.cluster_name
  namespace       = "dr-drill-mongodb-restore-target"
  service_account = "dr-drill-mongodb-runner"
  role_arn        = aws_iam_role.dr_drill_mongodb_restore_role.arn
}

# --- PostgreSQL WAL/PITR restore drill role (read-only) ---
# Bound to its OWN dedicated ServiceAccount (dr-drill-postgresql-runner).

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
  assume_role_policy = data.aws_iam_policy_document.dr_drill_pod_identity_trust.json
}

resource "aws_iam_role_policy" "dr_drill_postgresql_restore" {
  name   = "dr-drill-postgresql-restore-readonly"
  role   = aws_iam_role.dr_drill_postgresql_restore_role.id
  policy = data.aws_iam_policy_document.dr_drill_postgresql_restore.json
}

resource "aws_eks_pod_identity_association" "dr_drill_postgresql" {
  cluster_name    = var.cluster_name
  namespace       = "dr-drill-uat"
  service_account = "dr-drill-postgresql-runner"
  role_arn        = aws_iam_role.dr_drill_postgresql_restore_role.arn
}

# Same rationale as dr_drill_mongodb_restore_target above: the actual WAL/
# PITR S3 reads happen inside the CNPG-managed Postgres pod running in its
# OWN fixed namespace (dr-drill-postgresql-restore-target), under the SAME
# ServiceAccount name (spec.serviceAccountName on the CNPG Cluster manifest
# in scripts/dr-drill-postgresql-restore.sh) -- not in the orchestrator pod,
# which only does the identity guard check. Reuses the same read-only role.
resource "aws_eks_pod_identity_association" "dr_drill_postgresql_restore_target" {
  cluster_name    = var.cluster_name
  namespace       = "dr-drill-postgresql-restore-target"
  service_account = "dr-drill-postgresql-runner"
  role_arn        = aws_iam_role.dr_drill_postgresql_restore_role.arn
}

# --- ClickHouse backup+restore drill role (read+write, own bucket ONLY) ---
# Unlike the two roles above, this one also creates backups (Task 3 runs
# `clickhouse-backup create` + `upload`), so it needs s3:PutObject -- but
# strictly scoped to its own dedicated bucket, never oms-pbm-backups or
# oms-postgresql-wal-archive. Used by the DRILL's own CronJob pod (the
# operator-machine/CI-runner side of the script: `aws s3 ls` verification,
# and the throwaway restore-target pod) -- NOT by the live SigNoz ClickHouse
# pod itself, which uses its own dedicated role below (D15).

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
  assume_role_policy = data.aws_iam_policy_document.dr_drill_pod_identity_trust.json
}

resource "aws_iam_role_policy" "dr_drill_clickhouse_backup" {
  name   = "dr-drill-clickhouse-backup-scoped"
  role   = aws_iam_role.dr_drill_clickhouse_backup_role.id
  policy = data.aws_iam_policy_document.dr_drill_clickhouse_backup.json
}

resource "aws_eks_pod_identity_association" "dr_drill_clickhouse" {
  cluster_name    = var.cluster_name
  namespace       = "dr-drill-uat"
  service_account = "dr-drill-clickhouse-runner"
  role_arn        = aws_iam_role.dr_drill_clickhouse_backup_role.arn
}

# Same rationale again: the orchestrator pod above only does `aws s3 ls`
# verification of the just-created backup; the actual restore-side S3
# GetObject reads happen inside the `clickhouse-backup` container of the
# throwaway restore-target pod, which runs in its OWN fixed namespace
# (dr-drill-clickhouse-restore-target) under the SAME ServiceAccount name.
# Reuses the same read+write, own-bucket-only role (no new IAM role
# needed) -- this is safe because the restore-target pod also only ever
# touches the dedicated oms-signoz-clickhouse-backups bucket, same as the
# orchestrator.
resource "aws_eks_pod_identity_association" "dr_drill_clickhouse_restore_target" {
  cluster_name    = var.cluster_name
  namespace       = "dr-drill-clickhouse-restore-target"
  service_account = "dr-drill-clickhouse-runner"
  role_arn        = aws_iam_role.dr_drill_clickhouse_backup_role.arn
}

# --- Live SigNoz ClickHouse backup-creation role (write-only, own bucket) ---
# The `clickhouse-backup` sidecar added to the LIVE SigNoz ClickHouse pod
# (gitops/signoz/base/helmreleases.yaml) runs `clickhouse-backup create` +
# `upload` + `delete local` INSIDE that pod via `kubectl exec` -- those
# commands execute under the live pod's OWN identity, not the drill
# CronJob's identity. The live pod therefore needs its own Pod Identity
# association, scoped write-only (no s3:GetObject -- it never restores from
# here) to the same dedicated backup bucket. See D15.

data "aws_iam_policy_document" "signoz_clickhouse_backup_writer" {
  statement {
    sid    = "ClickhouseBackupWriteOnly"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::oms-signoz-clickhouse-backups",
      "arn:aws:s3:::oms-signoz-clickhouse-backups/*",
    ]
  }
}

resource "aws_iam_role" "signoz_clickhouse_backup_writer_role" {
  name               = "signoz-clickhouse-backup-writer-role"
  assume_role_policy = data.aws_iam_policy_document.dr_drill_pod_identity_trust.json
}

resource "aws_iam_role_policy" "signoz_clickhouse_backup_writer" {
  name   = "signoz-clickhouse-backup-writeonly"
  role   = aws_iam_role.signoz_clickhouse_backup_writer_role.id
  policy = data.aws_iam_policy_document.signoz_clickhouse_backup_writer.json
}

resource "aws_eks_pod_identity_association" "signoz_clickhouse_backup_writer" {
  cluster_name    = var.cluster_name
  namespace       = "signoz"
  service_account = "signoz-clickhouse-workload"
  role_arn        = aws_iam_role.signoz_clickhouse_backup_writer_role.arn
}

# NOTE: this repo's convention is Terraform-manages-AWS-only; Kubernetes
# objects are always created via GitOps/kubectl scripts (see
# scripts/create-signoz-root-user-secret.sh), never via the `kubernetes`
# Terraform provider (verified: no other root in this repo defines any
# kubernetes_* resource). The role ARNs are exposed as outputs; a bootstrap
# script (Step 3b below) creates the ServiceAccounts referenced above (Pod
# Identity associates a role directly with an existing ServiceAccount name/
# namespace -- no annotation is required on the ServiceAccount itself,
# unlike IRSA).

output "dr_drill_mongodb_role_arn" {
  value = aws_iam_role.dr_drill_mongodb_restore_role.arn
}

output "dr_drill_postgresql_role_arn" {
  value = aws_iam_role.dr_drill_postgresql_restore_role.arn
}

output "dr_drill_clickhouse_role_arn" {
  value = aws_iam_role.dr_drill_clickhouse_backup_role.arn
}

output "signoz_clickhouse_backup_writer_role_arn" {
  value = aws_iam_role.signoz_clickhouse_backup_writer_role.arn
}

