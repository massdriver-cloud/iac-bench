resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  project  = var.project_id
  cluster  = google_container_cluster.this.name
  location = google_container_cluster.this.location

  # Autoscaling counts are per zone for regional clusters.
  autoscaling {
    min_node_count = each.value.min_nodes
    max_node_count = each.value.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    spot         = each.value.spot
    image_type   = "COS_CONTAINERD"

    service_account = google_service_account.nodes.email
    # Access is controlled by IAM on the node SA and Workload Identity, not by legacy scopes.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels          = each.value.labels
    resource_labels = local.common_labels

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    # Block the legacy node metadata endpoints; pods get metadata via GKE's metadata server.
    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    precondition {
      condition     = !local.is_prod || each.value.min_nodes >= 1
      error_message = "Production node pool \"${each.key}\" must keep min_nodes >= 1 in every zone."
    }
  }
}
