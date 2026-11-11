terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# Credentials come from the environment (GOOGLE_CREDENTIALS /
# GOOGLE_APPLICATION_CREDENTIALS / the ADC chain). The provider block only
# pins project and region so that the module is explicit about where it lands;
# authentication itself is left to the standard credential chain.
provider "google" {
  project = var.project_id
  region  = var.region
}
