terraform {
  required_version = ">= 1.3.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.2.0"
    }
  }
}

# This module is applied directly as a root module, so it carries its own
# provider configuration. Credentials come from the environment.
provider "google" {
  project = var.project_id
  region  = var.region
}
