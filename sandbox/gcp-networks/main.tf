# Networks the GCP briefs describe, one custom-mode VPC per environment named
# apps-<env>. Every network has private services access (G002, Cloud SQL);
# staging and prod also have a GKE subnet in every US region with secondary
# ranges for pods and services (G005). No NAT, routers or instances: nothing
# here bills. Applied once to the benchmark project; models look these up by
# name.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

variable "project" {
  description = "Sandbox project that holds the environment networks."
  type        = string
}

provider "google" {
  project = var.project
}

variable "environments" {
  description = "Environment networks: the /16 allocated to private services access, and the /12 GKE subnets are carved from (null for none)."
  type = map(object({
    services_range = string
    gke_block      = optional(string)
  }))
  default = {
    dev     = { services_range = "10.10.0.0/16" }
    staging = { services_range = "10.11.0.0/16", gke_block = "10.32.0.0/12" }
    prod    = { services_range = "10.12.0.0/16", gke_block = "10.48.0.0/12" }
  }
}

variable "regions" {
  description = "Regions that hold a GKE subnet in every environment network."
  type        = list(string)
  default = [
    "us-central1", "us-east1", "us-east4", "us-east5", "us-south1",
    "us-west1", "us-west2", "us-west3", "us-west4",
  ]
}

locals {
  # One /16 per region and environment: nodes /20, services /20, pods /17.
  subnets = {
    for pair in setproduct([for k, v in var.environments : k if v.gke_block != null], range(length(var.regions))) :
    "${pair[0]}/${var.regions[pair[1]]}" => {
      env    = pair[0]
      region = var.regions[pair[1]]
      block  = cidrsubnet(var.environments[pair[0]].gke_block, 4, pair[1])
    }
  }
}

resource "google_compute_network" "env" {
  for_each                = var.environments
  name                    = "apps-${each.key}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "gke" {
  for_each                 = local.subnets
  name                     = "apps-${each.value.env}-gke-${each.value.region}"
  network                  = google_compute_network.env[each.value.env].id
  region                   = each.value.region
  ip_cidr_range            = cidrsubnet(each.value.block, 4, 0)
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet(each.value.block, 1, 1)
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(each.value.block, 4, 1)
  }
}

resource "google_project_service" "servicenetworking" {
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_global_address" "services" {
  for_each      = var.environments
  name          = "apps-${each.key}-services"
  network       = google_compute_network.env[each.key].id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", each.value.services_range)[0]
  prefix_length = tonumber(split("/", each.value.services_range)[1])
}

resource "google_service_networking_connection" "services" {
  for_each                = var.environments
  network                 = google_compute_network.env[each.key].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.services[each.key].name]
  depends_on              = [google_project_service.servicenetworking]
}
