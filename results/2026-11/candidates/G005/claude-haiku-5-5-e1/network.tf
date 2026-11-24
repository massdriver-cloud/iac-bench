# The network team owns the VPCs and GKE subnets. This module only reads them.

locals {
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"
}

data "google_compute_network" "vpc" {
  project = var.project_id
  name    = local.vpc_name
}

data "google_compute_subnetwork" "gke" {
  project = var.project_id
  region  = var.region
  name    = local.subnet_name
}
