resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  name       = each.key
  location   = var.region
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
  node_count = lookup(each.value, "initial_node_count", 1)

  autoscaling {
    min_node_count = lookup(each.value, "min_count", 1)
    max_node_count = lookup(each.value, "max_count", 5)
  }

  management {
    auto_repair  = lookup(each.value, "auto_repair", true)
    auto_upgrade = lookup(each.value, "auto_upgrade", true)
  }

  node_config {
    machine_type = lookup(each.value, "machine_type", "e2-standard-4")
    disk_size_gb = lookup(each.value, "disk_size_gb", 100)
    disk_type    = lookup(each.value, "disk_type", "pd-balanced")
    preemptible  = lookup(each.value, "preemptible", false)
    spot         = lookup(each.value, "spot", false)

    service_account = local.node_service_account_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = merge(
      local.default_labels,
      lookup(each.value, "labels", {})
    )

    tags = lookup(each.value, "node_tags", [])

    shielded_instance_config {
      enable_secure_boot          = var.enable_secure_boot
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    dynamic "taint" {
      for_each = lookup(each.value, "taints", [])
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
