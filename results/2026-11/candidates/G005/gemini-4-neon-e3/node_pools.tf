################################################################################
# Dedicated system node pool for GKE-managed infrastructure components
################################################################################

resource "google_container_node_pool" "system" {
  count = var.enable_system_node_pool ? 1 : 0

  name_prefix       = "system-"
  project           = local.project_id
  location          = var.region
  cluster           = google_container_cluster.this.name
  node_locations    = length(var.node_locations) > 0 ? var.node_locations : null
  max_pods_per_node = var.default_max_pods_per_node

  initial_node_count = var.system_node_pool.min_node_count

  autoscaling {
    min_node_count  = var.system_node_pool.min_node_count
    max_node_count  = var.system_node_pool.max_node_count
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = var.system_node_pool.max_surge
    max_unavailable = var.system_node_pool.max_unavailable
  }

  network_config {
    enable_private_nodes = true
  }

  node_config {
    machine_type      = var.system_node_pool.machine_type
    disk_size_gb      = var.system_node_pool.disk_size_gb
    disk_type         = var.system_node_pool.disk_type
    boot_disk_kms_key = var.system_node_pool.boot_disk_kms_key
    image_type        = "COS_CONTAINERD"

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      "pool"        = "system"
      "environment" = var.environment
    }

    resource_labels = merge(local.common_labels, {
      node-pool = "system"
    })

    tags = [
      local.node_network_tag,
      "${local.node_network_tag}-system",
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Isolate GKE-managed system pods (kube-dns, konnectivity, metrics-server, etc.)
    # from product team workloads; GKE automatically adds matching tolerations.
    taint {
      key    = "components.gke.io/gke-managed-components"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    gcfs_config {
      enabled = var.system_node_pool.enable_image_streaming
    }

    gvnic {
      enabled = true
    }

    kubelet_config {
      pod_pids_limit = 4096
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [initial_node_count]
  }
}

################################################################################
# Product team workload node pools
################################################################################

resource "google_container_node_pool" "workloads" {
  for_each = var.node_pools

  name_prefix       = "${each.key}-"
  project           = local.project_id
  location          = var.region
  cluster           = google_container_cluster.this.name
  node_locations    = length(each.value.node_locations) > 0 ? each.value.node_locations : (length(var.node_locations) > 0 ? var.node_locations : null)
  max_pods_per_node = coalesce(each.value.max_pods_per_node, var.default_max_pods_per_node)

  initial_node_count = each.value.min_node_count

  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
    location_policy = each.value.location_policy
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
        node_pool_soak_duration = each.value.blue_green_node_pool_soak_duration
        standard_rollout_policy {
          batch_percentage    = each.value.blue_green_batch_percentage
          batch_soak_duration = each.value.blue_green_batch_soak_duration
        }
      }
    }
  }

  network_config {
    enable_private_nodes = true
  }

  node_config {
    machine_type      = each.value.machine_type
    disk_size_gb      = each.value.disk_size_gb
    disk_type         = each.value.disk_type
    boot_disk_kms_key = each.value.boot_disk_kms_key
    image_type        = each.value.image_type
    spot              = each.value.spot

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(
      {
        "pool"        = each.key
        "environment" = var.environment
      },
      each.value.labels
    )

    resource_labels = merge(local.common_labels, {
      node-pool = each.key
    })

    tags = distinct(concat(
      [
        local.node_network_tag,
        "${local.node_network_tag}-${each.key}",
      ],
      each.value.tags
    ))

    metadata = merge(
      each.value.metadata,
      {
        disable-legacy-endpoints = "true"
      }
    )

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    gcfs_config {
      enabled = each.value.enable_image_streaming
    }

    gvnic {
      enabled = each.value.enable_gvnic
    }

    kubelet_config {
      pod_pids_limit = each.value.pod_pids_limit
    }

    dynamic "sandbox_config" {
      for_each = each.value.enable_gvisor ? [1] : []
      content {
        type = "GVISOR"
      }
    }

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    dynamic "guest_accelerator" {
      for_each = each.value.guest_accelerators
      content {
        type  = guest_accelerator.value.type
        count = guest_accelerator.value.count

        dynamic "gpu_driver_installation_config" {
          for_each = guest_accelerator.value.gpu_driver_installation_config != null ? [guest_accelerator.value.gpu_driver_installation_config] : []
          content {
            gpu_driver_version = gpu_driver_installation_config.value.gpu_driver_version
          }
        }
      }
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [initial_node_count]
  }
}
