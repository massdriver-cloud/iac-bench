# ---------------------------------------------------------------------------
# Node pools. Every pool (primary + additional) is autoscaled across zones,
# auto-repaired, auto-upgraded with zero-unavailability surge upgrades, and
# hardened identically.
# ---------------------------------------------------------------------------

resource "google_container_node_pool" "pools" {
  for_each = local.node_pools

  name     = each.key
  cluster  = google_container_cluster.this.id
  location = var.region

  autoscaling {
    min_node_count = each.value.min_node_count
    max_node_count = each.value.max_node_count
    # Keep capacity balanced across zones so a zone failure never takes out
    # a disproportionate share of a pool.
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
    disk_type    = each.value.disk_type
    disk_size_gb = each.value.disk_size_gb
    spot         = each.value.spot

    service_account = google_service_account.nodes.email

    # Full scope + IAM on the dedicated SA is the Google-recommended pattern;
    # coarse OAuth scopes are legacy. Workload Identity gates pod access.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(
      local.common_labels,
      { node-pool = each.key },
      each.value.labels,
    )

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

    # Network tag for the network team's firewall rules.
    tags = ["gke-${var.cluster_name}"]

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  # Make sure the node identity can actually log/monitor/pull before nodes
  # boot, otherwise first-boot agents fail.
  depends_on = [google_project_iam_member.node_roles]

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = each.value.min_node_count <= each.value.max_node_count
      error_message = "Node pool \"${each.key}\": min_node_count must not exceed max_node_count."
    }
    precondition {
      condition     = each.value.disk_size_gb >= 50
      error_message = "Node pool \"${each.key}\": disk_size_gb must be at least 50 GB."
    }
  }
}
