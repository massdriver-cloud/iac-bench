# -----------------------------------------------------------------------------
# Regional Production GKE Standard Cluster
# -----------------------------------------------------------------------------

resource "google_container_cluster" "this" {
  name        = var.cluster_name
  project     = var.project_id
  location    = var.region
  description = coalesce(var.description, "Shared ${var.environment} GKE Standard cluster (${var.cluster_name}) in ${var.region}")

  node_locations      = var.node_locations
  deletion_protection = var.deletion_protection
  resource_labels     = local.common_labels

  # GKE Standard mode: remove the immutable default pool and manage dedicated node pools
  remove_default_node_pool = true
  initial_node_count       = 1

  # Pre-provisioned environment VPC and regional subnet (<vpc>-gke-<region>)
  network                                  = local.network_self_link
  subnetwork                               = local.subnetwork_self_link
  networking_mode                          = "VPC_NATIVE"
  datapath_provider                        = "ADVANCED_DATAPATH"
  enable_cilium_clusterwide_network_policy = var.enable_cilium_clusterwide_network_policy
  default_max_pods_per_node                = var.default_max_pods_per_node

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = var.enable_master_global_access
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Bootstrap temporary default pool with hardened node identity so no GCE default SA is ever attached
  node_config {
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"
    disk_size_gb    = 50
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

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

  # Security & Multi-Tenancy Hardening
  enable_shielded_nodes = true
  enable_legacy_abac    = false

  anonymous_authentication_config {
    mode = "LIMITED"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = local.workload_identity_pool
  }

  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group != null ? [var.rbac_security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  database_encryption {
    state    = var.etcd_kms_key_name != null ? "ENCRYPTED" : "DECRYPTED"
    key_name = var.etcd_kms_key_name
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  security_posture_config {
    mode               = var.security_posture_mode
    vulnerability_mode = var.vulnerability_scanning_mode
  }

  secret_manager_config {
    enabled = var.enable_secret_manager_addon
  }

  # Release Channel & Maintenance Policy
  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }

    dynamic "maintenance_exclusion" {
      for_each = var.maintenance_exclusions
      content {
        exclusion_name = maintenance_exclusion.value.name
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time

        exclusion_options {
          scope = maintenance_exclusion.value.scope
        }
      }
    }
  }

  dynamic "notification_config" {
    for_each = var.notification_pubsub_topic != null ? [var.notification_pubsub_topic] : []
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  # Autoscaling, Add-ons & Multi-Team Observability
  cluster_autoscaling {
    autoscaling_profile = var.autoscaling_profile
  }

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  dynamic "gateway_api_config" {
    for_each = var.enable_gateway_api ? [1] : []
    content {
      channel = "CHANNEL_STANDARD"
    }
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    gce_persistent_disk_csi_driver_config {
      enabled = true
    }

    gcs_fuse_csi_driver_config {
      enabled = var.enable_gcs_fuse_csi_driver
    }

    dns_cache_config {
      enabled = var.enable_nodelocal_dnscache
    }

    gke_backup_agent_config {
      enabled = var.enable_backup_agent
    }
  }

  cost_management_config {
    enabled = var.enable_cost_allocation
  }

  logging_config {
    enable_components = var.logging_enabled_components
  }

  monitoring_config {
    enable_components = var.monitoring_enabled_components

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }

    advanced_datapath_observability_config {
      enable_metrics = var.enable_datapath_observability
      enable_relay   = var.enable_datapath_observability
    }
  }

  depends_on = [
    google_project_iam_member.nodes,
  ]

  lifecycle {
    # Bootstrap pool is removed immediately upon cluster creation; ignore subsequent drift on it
    ignore_changes = [
      node_config,
      initial_node_count,
    ]

    precondition {
      condition     = var.node_locations == null || alltrue([for z in var.node_locations : startswith(z, "${var.region}-")])
      error_message = "All zones in node_locations must belong to the configured region (${var.region})."
    }
  }
}

# -----------------------------------------------------------------------------
# Managed GKE Standard Node Pools
# -----------------------------------------------------------------------------

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name               = each.key
  project            = var.project_id
  location           = var.region
  cluster            = google_container_cluster.this.name
  node_locations     = each.value.node_locations
  initial_node_count = each.value.total_min_node_count >= 3 ? 1 : 0
  max_pods_per_node  = coalesce(each.value.max_pods_per_node, var.default_max_pods_per_node)

  autoscaling {
    total_min_node_count = each.value.total_min_node_count
    total_max_node_count = each.value.total_max_node_count
    location_policy      = each.value.location_policy
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
    machine_type    = each.value.machine_type
    image_type      = "COS_CONTAINERD"
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    spot            = each.value.spot
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

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
        "node_pool" = each.key
      }
    )

    tags = distinct(concat(["gke-${var.cluster_name}"], each.value.network_tags))

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

    gvnic {
      enabled = each.value.enable_gvnic
    }

    kubelet_config {
      pod_pids_limit = each.value.pod_pids_limit
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

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]

    precondition {
      condition     = each.value.node_locations == null || alltrue([for z in each.value.node_locations : startswith(z, "${var.region}-")])
      error_message = "All zones in node_pools[\"${each.key}\"].node_locations must belong to the configured region (${var.region})."
    }
  }
}
