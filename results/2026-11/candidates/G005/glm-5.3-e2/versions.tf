# ---------------------------------------------------------------------------
# Provider requirements
# ---------------------------------------------------------------------------
#
# This module is used directly as a root module (see minimal.tfvars) and can
# also be embedded as a child module by the platform team. The provider
# configuration below is only honoured when running this module standalone;
# when embedded, configure the google provider in the enclosing root module
# with the same project as `var.project_id`.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
}
