locals {
  system_pool = {
    machine_type      = var.system_node_pool.machine_type
    disk_size_gb      = var.system_node_pool.disk_size_gb
    disk_type         = var.system_node_pool.disk_type
    min_node_count    = var.system_node_pool.min_node_count
    max_node_count    = var.system_node_pool.max_node_count
    node_count        = var.system_node_pool.node_count
    max_pods_per_node = var.system_node_pool.max_pods_per_node
    labels            = {}
    spot              = false
    taints = [{
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_EXECUTE"
    }]
  }

  application_pools = {
    for name, pool in var.application_node_pools : name => {
      machine_type      = pool.machine_type
      disk_size_gb      = pool.disk_size_gb
      disk_type         = pool.disk_type
      min_node_count    = pool.min_node_count
      max_node_count    = pool.max_node_count
      node_count        = pool.node_count
      max_pods_per_node = pool.max_pods_per_node
      labels            = pool.labels
      spot              = pool.spot
      taints            = pool.taints
    }
  }

  node_pools = merge({ system = local.system_pool }, local.application_pools)
}

resource "google_container_node_pool" "this" {
  for_each = local.node_pools

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  node_locations    = var.node_locations
  node_count        = each.value.node_count
  max_pods_per_node = each.value.max_pods_per_node

  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # A surge node preserves capacity while a node is upgraded. This is
  # particularly important when min_node_count is one in each zone.
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

    service_account = google_service_account.nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = merge(each.value.labels, {
      environment = var.environment
      managed-by  = "opentofu"
      node-pool   = each.key
    })

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }

    gcfs_config {
      enabled = true
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

  # Nodes must not start before their telemetry and image-pull IAM is present.
  depends_on = [google_project_iam_member.node_operations]

  # The autoscaler, rather than Terraform, owns desired size after creation.
  lifecycle {
    ignore_changes = [node_count]
  }
}
