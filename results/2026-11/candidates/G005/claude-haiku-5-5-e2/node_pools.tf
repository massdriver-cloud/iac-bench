resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  # Autoscaling bounds are per zone. A regional cluster spans three zones, so
  # the pool runs between 3*min and 3*max nodes.
  autoscaling {
    min_node_count  = each.value.min_nodes_per_zone
    max_node_count  = each.value.max_nodes_per_zone
    location_policy = "BALANCED"
  }

  # Surge upgrades add one node before draining one, so capacity never drops
  # below the pool's current size during an upgrade.
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = each.value.machine_type
    disk_type    = each.value.disk_type
    disk_size_gb = each.value.disk_size_gb
    image_type   = "COS_CONTAINERD"
    spot         = each.value.spot
    labels       = each.value.labels

    service_account = google_service_account.nodes.email
    # Access is controlled by IAM roles on the service account and by Workload
    # Identity. The legacy scopes are not used.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Pods reach the metadata server only through GKE_METADATA, which is the
    # Workload Identity path. Legacy metadata endpoints are disabled.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

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
  }

  depends_on = [
    google_project_iam_member.node_roles,
  ]
}
