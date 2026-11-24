data "google_client_config" "current" {}

data "google_project" "current" {
  project_id = local.project_id
}

data "google_compute_network" "vpc" {
  project = local.project_id
  name    = local.vpc_name
}

data "google_compute_subnetwork" "subnet" {
  project = local.project_id
  region  = var.region
  name    = local.subnet_name
}
