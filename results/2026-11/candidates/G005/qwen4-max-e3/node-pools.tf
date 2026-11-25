# ---------------------------------------------------------------------------
# Managed node pools. All pools share the module's hardened node defaults:
# dedicated least-privilege service account, Shielded VMs (secure boot +
# integrity monitoring), GKE Metadata Server (Workload Identity), no legacy
# metadata endpoints, COS, auto-repair + auto-upgrade with surge upgrades.
# ---------------------------------------------------------------------------

resource "google_container_node_pool" "primary" {
  name     = "primary"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.id

  # null => spread across every zone in the region.
  node_locations = var.node_locations

  # Per-zone counts; with the default 3-zone region this is 3-9 nodes.
  initial_node_count = var.primary_node_pool.min_node_count

  autoscaling {
    min_node_count  = var.primary_node_pool.min_node_count
    max_node_count  = var.primary_node_pool.max_node_count
    location_policy = "BALANCED" # keep zones evenly populated for resilience
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.primary_node_pool.machine_type
    disk_size_gb = var.primary_node_pool.disk_size_gb
    disk_type    = var.primary_node_pool.disk_type
    image_type   = "COS_CONTAINERD"

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      environment = var.environment
      pool        = "primary"
    }

    tags = local.node_tags
  }

  lifecycle {
    ignore_changes = [
      version,            # managed by the release channel
      initial_node_count, # owned by the autoscaler after creation
    ]
  }
}

# ---------------------------------------------------------------------------
# Optional additional pools for specialised workloads (GPU, memory-heavy,
# isolated/tenant-dedicated via taints, or spot batch capacity).
# ---------------------------------------------------------------------------

resource "google_container_node_pool" "extra" {
  for_each = var.extra_node_pools

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.id

  node_locations     = var.node_locations
  initial_node_count = each.value.min_node_count

  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = "COS_CONTAINERD"
    spot         = each.value.spot

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = merge(
      {
        environment = var.environment
        pool        = each.key
      },
      each.value.labels,
    )

    tags = local.node_tags

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    ignore_changes = [
      version,
      initial_node_count,
    ]
  }
}
