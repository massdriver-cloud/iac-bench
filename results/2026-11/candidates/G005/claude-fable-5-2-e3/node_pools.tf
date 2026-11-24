resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  project  = local.project_id
  name     = each.key
  cluster  = google_container_cluster.this.name
  location = google_container_cluster.this.location

  # Null: same zones as the cluster.
  node_locations = each.value.zones

  # Only used at creation; the autoscaler owns the node count afterwards.
  initial_node_count = each.value.min_nodes_per_zone

  autoscaling {
    min_node_count = each.value.min_nodes_per_zone
    max_node_count = each.value.max_nodes_per_zone
    # Keep on-demand pools evenly spread over zones; let Spot pools take
    # capacity wherever it is available.
    location_policy = each.value.spot ? "ANY" : "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Upgrades add a fresh node before draining an old one, so capacity never
  # drops below what the workloads are running on.
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

    # Dedicated least-privilege identity; access is governed by IAM roles on
    # that account, not by legacy scopes.
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels          = each.value.labels
    resource_labels = local.labels

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Pods see the GKE metadata server, never the node's own credentials.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  timeouts {
    create = "45m"
    update = "60m"
    delete = "45m"
  }

  lifecycle {
    # initial_node_count is create-only; changing min_nodes_per_zone later
    # must adjust the autoscaler, not recreate the pool.
    ignore_changes = [initial_node_count]
  }
}
