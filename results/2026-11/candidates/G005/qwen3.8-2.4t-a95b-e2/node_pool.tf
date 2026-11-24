# -----------------------------------------------------------------------------
# Default (and only) node pool, managed separately from the cluster so it can
# change without touching the control plane. It is regional: with location set
# to the region and no explicit node_locations, GKE spreads the nodes across
# all zones of the region, matching the regional control plane.
# -----------------------------------------------------------------------------
resource "google_container_node_pool" "default" {
  name     = "default-pool"
  project  = var.project_id
  cluster  = google_container_cluster.this.name
  location = var.region

  # Starting size per zone; the autoscaler then moves between the configured
  # bounds. Counts in autoscaling are per zone for a regional pool.
  initial_node_count = var.min_nodes_per_zone

  autoscaling {
    min_node_count = var.min_nodes_per_zone
    max_node_count = var.max_nodes_per_zone
  }

  management {
    auto_repair  = true
    auto_upgrade = true # follows the cluster's release channel
  }

  # Surge upgrades: add a node first, drain, then remove. No capacity loss.
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = var.node_disk_type

    oauth_scopes    = local.node_oauth_scopes
    service_account = google_service_account.nodes.email
    labels          = var.node_labels
    tags            = var.node_network_tags
    metadata        = { "disable-legacy-endpoints" = "true" }

    # Boot integrity: measured boot + secure boot on every node.
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # GKE Metadata Server: lets pods exchange their Kubernetes service account
    # for Google Cloud credentials (Workload Identity).
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}
