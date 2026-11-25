# Node pools are managed here, separate from the cluster resource, so pools
# can be added, removed or resized without recreating the cluster.
resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  # null => every zone in the region (recommended for availability).
  node_locations = each.value.node_locations

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  max_pods_per_node = each.value.max_pods_per_node

  management {
    auto_repair  = each.value.auto_repair
    auto_upgrade = each.value.auto_upgrade
  }

  # Surge upgrades: extra capacity comes up before any existing node drains,
  # so a multi-zone pool keeps serving during upgrades.
  upgrade_settings {
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    machine_type    = each.value.machine_type
    image_type      = each.value.image_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    local_ssd_count = each.value.local_ssd_count
    spot            = each.value.spot

    # Dedicated least-privilege identity (see iam.tf) — never the default
    # compute service account.
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Kubernetes node labels versus GCP resource labels.
    labels          = each.value.labels
    resource_labels = merge(var.labels, each.value.resource_labels)

    dynamic "taint" {
      for_each = { for t in each.value.taints : "${t.key}:${t.value}:${t.effect}" => t }
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Route metadata requests through the GKE metadata server — required for
    # Workload Identity, and it prevents pods from using the node identity
    # directly.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Image streaming: containers start before the full image is pulled.
    gcfs_config {
      enabled = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}
