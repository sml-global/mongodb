aws_region                      = "ap-east-1"
expected_account_id             = "632674123947"
environment                     = "prod"
cluster_name                    = "oms-prod-eks-cluster"
eks_platform_state_bucket       = "sml-oms-prod-tfstate-632674123947"
eks_platform_state_key          = "oms/prod/eks-platform.tfstate"
eks_platform_state_use_lockfile = true

# Operator must populate before real prod workloads run.
identities = {}
