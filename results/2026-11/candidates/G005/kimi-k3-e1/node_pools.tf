# Node pools are managed separately from the cluster so they can be added,
# removed and resized without recreating the control plane.
resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  # Defaults to the cluster's zones when not set on the pool.
  node_locations = each.value.node_locations

  # The cluster autoscaler keeps the pool between these bounds per zone and
  # balances growth across zones.
  autoscaling {
    min_node_count  = each.value.min_count
    max_node_count  = each.value.max_count
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Surge upgrades keep capacity available during node upgrades: one extra
  # node comes up before any node is drained, and no node is taken down
  # without a replacement being ready.
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    image_type   = each.value.image_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    spot         = each.value.spot

    # Least-privilege, per-cluster node identity (see iam.tf).
    service_account = local.node_service_account_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = each.value.labels
    tags   = each.value.tags

    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    # Serve Pod identity through the GKE metadata server (Workload Identity).
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    gvnic {
      enabled = true
    }

    # Image streaming for fast, lazy image pulls.
    gcfs_config {
      enabled = true
    }

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  timeouts {
    create = "45m"
    update = "60m"
    delete = "45m"
  }
}
