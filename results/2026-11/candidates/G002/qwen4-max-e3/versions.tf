terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# The Google provider is configured for the project that owns the apps-*
# networks (project/credentials/region come from the environment). Instances
# are created in that same project; nothing here re-specifies it.
provider "google" {}
