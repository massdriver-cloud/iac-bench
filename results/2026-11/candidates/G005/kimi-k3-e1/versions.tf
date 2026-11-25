terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30.0, < 7.0.0"
    }
  }
}

# This module is consumed directly as a root module, so it configures the
# provider itself from the per-cluster inputs. Credentials come from the
# environment (Application Default Credentials).
provider "google" {
  project = var.project_id
  region  = var.region
}
