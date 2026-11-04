# This module is applied directly as a root module, so a provider block is
# appropriate here. Credentials come from the environment (ADC); project and
# region follow the module inputs so no environment-side configuration is
# required.
provider "google" {
  project = var.project_id
  region  = var.region
}
