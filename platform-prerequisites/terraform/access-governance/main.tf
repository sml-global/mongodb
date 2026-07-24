resource "aws_accessanalyzer_analyzer" "uat_account" {
  analyzer_name = "uat-account-access-analyzer"
  type          = "ACCOUNT"
}
