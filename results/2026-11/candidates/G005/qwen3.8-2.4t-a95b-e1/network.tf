# ---------------------------------------------------------------------------
# Egress for private nodes: Cloud Router + Cloud NAT on the GKE subnet.
# Private nodes have no public IPs, so without NAT (or a network-team
# equivalent) they cannot pull images from public registries.
# ---------------------------------------------------------------------------

resource "google_compute_router" "this" {
  count = var.enable_cloud_nat ? 1 : 0

  name    = "${var.cluster_name}-router"
  project = var.project_id
  region  = var.region
  network = local.network_url

  description = "Cloud Router for GKE cluster ${var.cluster_name} (managed by the GKE Standard platform module)."
}

resource "google_compute_router_nat" "this" {
  count = var.enable_cloud_nat ? 1 : 0

  name    = "${var.cluster_name}-nat"
  project = var.project_id
  region  = var.region
  router  = google_compute_router.this[0].name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = local.subnetwork_url
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
