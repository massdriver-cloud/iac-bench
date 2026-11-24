resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  project  = local.project_id
  cluster  = google_container_cluster.this.name
  location = var.region
  name     = each.key

  # Node counts are per zone; a regional pool runs in every zone of the region.
  initial_node_count = each.value.min_nodes_per_zone

  autoscaling {
    min_node_count  = each.value.min_nodes_per_zone
    max_node_count  = each.value.max_nodes_per_zone
    location_policy = each.value.spot ? "ANY" : "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Add a node before draining one, so upgrades never reduce capacity.
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    image_type   = "COS_CONTAINERD"
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    spot         = each.value.spot

    # Dedicated least-privilege identity; what it may do is controlled by IAM, not scopes.
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Pods get their own Workload Identity credentials from the GKE metadata
    # server and cannot read the node's credentials.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    kubelet_config {
      insecure_kubelet_readonly_port_enabled = "FALSE"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels          = each.value.labels
    resource_labels = local.labels
    tags            = [local.node_network_tag]

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
    # Only used at creation; afterwards the autoscaler owns the node count.
    # Without this, changing min_nodes_per_zone would replace the pool.
    ignore_changes = [initial_node_count]
  }

  depends_on = [google_project_iam_member.nodes]
}
