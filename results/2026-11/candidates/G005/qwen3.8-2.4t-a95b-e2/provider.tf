# The provider takes its project and region from the module inputs so the same
# module can be pointed at any environment (apps-staging / apps-prod) without
# any extra provider configuration. Credentials are taken from the environment
# (GOOGLE_CREDENTIALS / application default credentials).
provider "google" {
  project = var.project_id
  region  = var.region
}
