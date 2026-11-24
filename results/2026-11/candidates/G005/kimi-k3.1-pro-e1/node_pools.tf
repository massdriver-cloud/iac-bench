resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  project  = var.project_id
  cluster  = google_container_cluster.this.name
  location = var.region
  name     = each.key

  node_locations    = length(var.node_locations) > 0 ? sort(tolist(var.node_locations)) : null
  max_pods_per_node = each.value.max_pods_per_node

  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
    location_policy = each.value.location_policy
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
    machine_type    = each.value.machine_type
    image_type      = each.value.image_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    local_ssd_count = each.value.local_ssd_count
    spot            = each.value.spot
    preemptible     = false

    service_account = google_service_account.nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    tags = each.value.tags
    labels = merge(each.value.labels, {
      cluster   = var.cluster_name
      node_pool = replace(each.key, "_", "-")
    })

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
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
