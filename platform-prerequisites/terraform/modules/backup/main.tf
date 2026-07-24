check "uat_retention_floor" {
  assert {
    condition     = var.deployment_environment != "uat" || var.backup_retention_days >= 35
    error_message = "UAT backup_retention_days must be at least 35."
  }
}

resource "aws_backup_vault" "this" {
  name        = "${var.name_prefix}-vault"
  kms_key_arn = var.backup_kms_key_arn
}

resource "aws_backup_vault_lock_configuration" "this" {
  backup_vault_name  = aws_backup_vault.this.name
  min_retention_days = var.vault_min_retention_days
  max_retention_days = var.vault_max_retention_days
}

resource "aws_backup_plan" "this" {
  name = "${var.name_prefix}-plan"

  rule {
    rule_name         = "${var.name_prefix}-daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 2 * * ? *)"

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }
}

resource "aws_backup_selection" "this" {
  iam_role_arn = var.backup_service_role_arn
  name         = "${var.name_prefix}-selection"
  plan_id      = aws_backup_plan.this.id
  resources    = var.backup_target_resource_arns
}