terraform {
  backend "s3" {
    # Backend configuration provided via -backend-config flags during terraform init
    # Supports dynamic configuration for sandbox (us-east-1) and UAT (ap-east-1) environments
  }
}
