# This module is applied as a root module, once per cluster, so the provider
# configuration lives here. Cloud credentials come from the environment
# (GOOGLE_APPLICATION_CREDENTIALS or Application Default Credentials).
provider "google" {
  project = var.project_id
  region  = var.region
}
