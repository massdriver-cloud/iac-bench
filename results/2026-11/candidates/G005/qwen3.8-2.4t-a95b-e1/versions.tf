terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.40.0, < 7.0.0"
    }
  }
}

# Root module: provider is configured here so the module can be applied
# directly. Credentials come from the environment (ADC / GOOGLE_CREDENTIALS).
provider "google" {
  project = var.project_id
  region  = var.region
}
