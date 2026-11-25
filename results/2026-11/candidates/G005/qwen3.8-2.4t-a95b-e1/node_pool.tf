# ---------------------------------------------------------------------------
# Node pools. Regional pools spread evenly across the region's zones
# (location_policy = BALANCED) so the cluster survives a zone failure.
# ---------------------------------------------------------------------------

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  initial_node_count = max(each.value.min_node_count, 1)

  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Surge upgrades: add capacity first, never remove capacity first.
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = each.value.image_type
    spot         = each.value.spot

    # Module-managed node SA by default; cloud-platform scope is sufficient
    # because workload access to GCP APIs is governed by Workload Identity.
    service_account = coalesce(each.value.service_account, google_service_account.nodes.email)
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = each.value.labels

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  # Nodes should not boot before their service account has its IAM roles.
  depends_on = [google_project_iam_member.node_sa_roles]
}
