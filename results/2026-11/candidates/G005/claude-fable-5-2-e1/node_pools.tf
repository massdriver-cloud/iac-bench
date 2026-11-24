resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  project  = local.project_id
  name     = each.key
  cluster  = google_container_cluster.this.name
  location = google_container_cluster.this.location

  # null = every zone of the (regional) cluster.
  node_locations = each.value.zones

  # Per zone. Only used at creation; the autoscaler owns the count afterwards.
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

  # Add a new node before draining an old one: upgrades never reduce capacity.
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

    # Dedicated least-privilege identity. The broad scope is deliberate: access
    # is governed by the service account's IAM roles, not by legacy scopes.
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = each.value.labels

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    # Pods get credentials from the GKE metadata server (Workload Identity),
    # never from the node's own service account.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "45m"
    update = "90m"
    delete = "45m"
  }

  depends_on = [google_project_iam_member.nodes]
}
