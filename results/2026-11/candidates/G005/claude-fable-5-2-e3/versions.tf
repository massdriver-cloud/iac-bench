terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source = "hashicorp/google"
      # 6.14 is the first release line with a stable DNS-based control plane
      # endpoint, which is how this module exposes the Kubernetes API.
      version = ">= 6.14.0, < 8.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11.0"
    }
  }
}

# The module is applied directly as a root module, one state per cluster.
# When var.project_id is null the project comes from the environment
# (GOOGLE_PROJECT / GOOGLE_CLOUD_PROJECT), like the credentials do.
provider "google" {
  project = var.project_id
  region  = var.region
}
