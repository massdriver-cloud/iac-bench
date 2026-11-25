resource "google_container_node_pool" "this" {
  for_each = local.all_node_pools

  name_prefix = each.value.name_prefix
  project     = var.project_id
  location    = var.region
  cluster     = google_container_cluster.this.id

  node_locations     = length(var.node_zones) > 0 ? var.node_zones : null
  initial_node_count = each.value.min_count_per_zone
  max_pods_per_node  = each.value.max_pods_per_node

  autoscaling {
    min_node_count  = each.value.min_count_per_zone
    max_node_count  = each.value.max_count_per_zone
    location_policy = each.value.spot ? "ANY" : "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = each.value.upgrade_strategy
    max_surge       = each.value.upgrade_strategy == "SURGE" ? each.value.max_surge : null
    max_unavailable = each.value.upgrade_strategy == "SURGE" ? each.value.max_unavailable : null

    dynamic "blue_green_settings" {
      for_each = each.value.upgrade_strategy == "BLUE_GREEN" ? [1] : []
      content {
        node_pool_soak_duration = "3600s"
        standard_rollout_policy {
          batch_percentage    = 0.25
          batch_soak_duration = "300s"
        }
      }
    }
  }

  network_config {
    enable_private_nodes = true
    create_pod_range     = false
    pod_range            = local.pods_range_name
  }

  node_config {
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    image_type      = "COS_CONTAINERD"
    spot            = each.value.spot
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    logging_variant = each.value.logging_variant

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Intercept GCE metadata server requests so pods cannot obtain node SA tokens
    # and must authenticate via Workload Identity Federation.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Optional Image Streaming (GCFS); requires containerfilesystem.googleapis.com.
    gcfs_config {
      enabled = var.enable_image_streaming
    }

    # Google Virtual NIC for optimal Dataplane V2 networking performance.
    gvnic {
      enabled = true
    }

    dynamic "sandbox_config" {
      for_each = each.value.enable_gvisor ? [1] : []
      content {
        type = "GVISOR"
      }
    }

    labels = merge(
      {
        "environment" = var.environment
        "node-pool"   = each.key
      },
      each.value.labels
    )

    resource_labels = merge(
      local.common_labels,
      {
        "node-pool" = each.key
      }
    )

    tags = distinct(concat(
      [
        local.cluster_network_tag,
        "${local.cluster_network_tag}-${each.key}",
      ],
      each.value.tags
    ))

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
    create_before_destroy = true
    ignore_changes        = [initial_node_count]
  }

  depends_on = [
    google_project_iam_member.node_default,
    google_project_iam_member.node_artifact_registry,
  ]
}
