# ------------------------------------------------------------------------------
# Managed Node Pools (GKE Standard)
# ------------------------------------------------------------------------------
# Each node pool uses name_prefix + create_before_destroy so immutable changes
# (e.g., machine_type, disk_size_gb, taints) spin up replacement nodes before
# draining and removing the old pool, preventing workload downtime.

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  project            = var.project_id
  name_prefix        = "${each.key}-"
  cluster            = google_container_cluster.this.name
  location           = var.region
  node_locations     = length(each.value.node_locations) > 0 ? each.value.node_locations : null
  initial_node_count = each.value.min_nodes_per_zone
  max_pods_per_node  = each.value.max_pods_per_node

  autoscaling {
    min_node_count = each.value.min_nodes_per_zone
    max_node_count = each.value.max_nodes_per_zone
    # Keep on-demand pools balanced evenly across zones for HA; allow Spot pools
    # to acquire capacity in whichever zone currently has Spot inventory.
    location_policy = each.value.spot ? "ANY" : "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = "COS_CONTAINERD"
    spot         = each.value.spot

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # High-performance virtual NIC for Dataplane V2.
    gvnic {
      enabled = each.value.enable_gvnic
    }

    # Image streaming accelerates pod startup when pulling from Artifact Registry
    # (GKE requires COS_CONTAINERD, non-pd-standard boot disk, and >= 100 GB).
    gcfs_config {
      enabled = (
        each.value.enable_image_streaming &&
        each.value.disk_type != "pd-standard" &&
        each.value.disk_size_gb >= 100
      )
    }

    # Shielded VM hardening.
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Route pod metadata requests through the GKE Metadata Server for Workload
    # Identity Federation; blocks pods from stealing node SA credentials.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    metadata = merge(
      {
        disable-legacy-endpoints = "true"
      },
      each.value.metadata,
    )

    labels = merge(
      {
        "node-pool" = each.key
      },
      each.value.node_labels,
    )

    resource_labels = merge(
      local.common_labels,
      {
        node_pool = each.key
      },
      each.value.resource_labels,
    )

    tags = distinct(concat(
      [
        local.cluster_node_tag,
        "gke-${var.cluster_name}-${each.key}",
      ],
      each.value.tags,
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
}
