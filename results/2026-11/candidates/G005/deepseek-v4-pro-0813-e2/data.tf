data "google_compute_network" "network" {
  name    = var.network_name
  project = var.project_id
}

data "google_compute_subnetwork" "gke_subnet" {
  name    = local.subnetwork_name
  region  = var.region
  project = var.project_id
}

locals {
  subnetwork_name = var.subnetwork_name != null ? var.subnetwork_name : "${var.network_name}-gke-${var.region}"
  node_locations  = length(var.node_locations) > 0 ? var.node_locations : null
}