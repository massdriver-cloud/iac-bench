###############################################################################
# Provider requirements.
#
# This module is applied directly as a root module. Credentials come from the
# environment (Application Default Credentials); the project is pinned to
# var.project_id so nothing depends on an ambient default project. Every
# resource also sets `project` explicitly for the same reason.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.20.0, < 7.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 4.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
}
