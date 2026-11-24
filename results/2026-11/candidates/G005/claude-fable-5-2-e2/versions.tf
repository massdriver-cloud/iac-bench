terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.30.0, < 7.0.0"
    }
  }
}

# Credentials come from the environment. The project is taken from
# var.project_id when set, otherwise from the environment (GOOGLE_PROJECT etc.).
provider "google" {
  project = var.project_id
  region  = var.region
}
