# -----------------------------------------------------------------------------
# Dedicated System Node Pool (GKE critical add-ons isolated from user workloads)
# -----------------------------------------------------------------------------

resource "google_container_node_pool" "system" {
  count = var.system_node_pool.enabled ? 1 : 0

  project        = var.project_id
  name           = "system"
  location       = var.region
  cluster        = google_container_cluster.this.name
  node_locations = length(var.node_locations) > 0 ? var.node_locations : null

  initial_node_count = var.system_node_pool.min_nodes_per_zone

  autoscaling {
    min_node_count  = var.system_node_pool.min_nodes_per_zone
    max_node_count  = var.system_node_pool.max_nodes_per_zone
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = var.system_node_pool.max_surge
    max_unavailable = var.system_node_pool.max_unavailable
  }

  node_config {
    machine_type      = var.system_node_pool.machine_type
    image_type        = "COS_CONTAINERD"
    disk_size_gb      = var.system_node_pool.disk_size_gb
    disk_type         = var.system_node_pool.disk_type
    boot_disk_kms_key = var.boot_disk_kms_key
    spot              = false

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(
      {
        "workload-tier" = "system"
      },
      var.system_node_pool.labels,
    )

    resource_labels = local.common_labels
    tags            = distinct(concat(local.base_network_tags, var.system_node_pool.network_tags))

    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    taint {
      key    = "components.gke.io/gke-managed-components"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

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
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}

# -----------------------------------------------------------------------------
# Workload Node Pools (Product team deployments)
# -----------------------------------------------------------------------------

resource "google_container_node_pool" "workload" {
  for_each = var.node_pools

  project        = var.project_id
  name           = each.key
  location       = var.region
  cluster        = google_container_cluster.this.name
  node_locations = length(var.node_locations) > 0 ? var.node_locations : null

  initial_node_count = each.value.min_nodes_per_zone

  autoscaling {
    min_node_count  = each.value.min_nodes_per_zone
    max_node_count  = each.value.max_nodes_per_zone
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    machine_type      = each.value.machine_type
    image_type        = "COS_CONTAINERD"
    disk_size_gb      = each.value.disk_size_gb
    disk_type         = each.value.disk_type
    boot_disk_kms_key = var.boot_disk_kms_key
    spot              = each.value.spot

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(
      {
        "node-pool" = each.key
      },
      each.value.labels,
    )

    resource_labels = local.common_labels
    tags            = distinct(concat(local.base_network_tags, each.value.network_tags))

    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

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
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}
