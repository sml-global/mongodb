terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

  required_providers {
    signoz = {
      source  = "SigNoz/signoz"
      version = "~> 0.0.14"
    }
  }
}

# Reads SIGNOZ_ENDPOINT / SIGNOZ_ACCESS_TOKEN from the environment by default
# (provider-native support) so no secret ever needs to be written to a .tf
# file or committed to git. See scripts/provision-signoz-observability.sh,
# which exports both before running terraform.
provider "signoz" {}
