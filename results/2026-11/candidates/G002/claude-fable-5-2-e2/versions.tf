terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.14.0, < 8.0.0"
    }
  }
}

# A null project falls back to the project configured in the environment
# (GOOGLE_PROJECT / GOOGLE_CLOUD_PROJECT / application default credentials).
provider "google" {
  project = var.project_id
  region  = var.region
}
