# The module is applied as a root module: the provider configuration lives
# here and authentication comes from the environment (Application Default
# Credentials, e.g. `gcloud auth application-default login`).

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.50" # the container resource schema this module targets
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
