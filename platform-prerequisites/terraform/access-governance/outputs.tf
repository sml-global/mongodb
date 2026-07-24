output "analyzer_arn" {
  value = aws_accessanalyzer_analyzer.uat_account.arn
}

output "analyzer_name" {
  value = aws_accessanalyzer_analyzer.uat_account.analyzer_name
}
