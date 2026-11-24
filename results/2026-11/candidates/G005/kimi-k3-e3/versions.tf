terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }
}

# This module is applied directly as a root module, so it configures the
# provider itself. Credentials come from the environment (GOOGLE_CREDENTIALS,
# gcloud application-default credentials, workload identity federation, ...).
provider "google" {
  project = var.project_id
  region  = var.region
}
