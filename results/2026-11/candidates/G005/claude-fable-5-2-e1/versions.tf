terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.30.0, < 8.0.0"
    }
  }
}

# Credentials come from the environment. The project does too unless
# var.project_id is set, in which case the variable wins.
provider "google" {
  project = var.project_id
  region  = var.region
}
