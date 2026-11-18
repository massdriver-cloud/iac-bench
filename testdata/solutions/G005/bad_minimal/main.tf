# What a quick, unhardened module looks like: a zonal cluster with its
# default node pool, default service account and public nodes, plus a Cloud
# NAT the network team never asked for.

variable "name" {
  description = "Cluster name."
  type        = string
}

variable "zone" {
  description = "Zone for the cluster."
  type        = string
  default     = "us-central1-a"
}

variable "network" {
  description = "VPC network name."
  type        = string
}

variable "subnetwork" {
  description = "Subnet name."
  type        = string
}

variable "node_count" {
  description = "Nodes in the default pool."
  type        = number
  default     = 3
}

variable "machine_type" {
  description = "Node machine type."
  type        = string
  default     = "e2-standard-4"
}

resource "google_compute_router" "nat" {
  name    = "${var.name}-nat"
  region  = substr(var.zone, 0, length(var.zone) - 2)
  network = var.network
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name}-nat"
  router                             = google_compute_router.nat.name
  region                             = google_compute_router.nat.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_container_cluster" "this" {
  name                = var.name
  location            = var.zone
  network             = var.network
  subnetwork          = var.subnetwork
  initial_node_count  = var.node_count
  deletion_protection = false

  node_config {
    machine_type = var.machine_type
  }
}

output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}
