# -----------------------------------------------------------------------------
# GKE Standard Regional Cluster
# -----------------------------------------------------------------------------

resource "google_container_cluster" "this" {
  name                = var.cluster_name
  project             = var.project_id
  location            = var.region
  node_locations      = var.node_zones
  description         = coalesce(var.description, "Shared ${var.environment} GKE Standard cluster (${var.cluster_name}) in ${var.region}")
  deletion_protection = var.deletion_protection
  resource_labels     = local.effective_labels

  # GKE Standard with separately managed node pools
  remove_default_node_pool = true
  initial_node_count       = 1

  # Hardened bootstrap node_config for the temporary default pool during creation
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

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
  }

  # VPC-native networking using the network team's VPC, regional subnet, and secondary ranges
  networking_mode                          = "VPC_NATIVE"
  network                                  = local.vpc_self_link
  subnetwork                               = local.subnet_self_link
  datapath_provider                        = "ADVANCED_DATAPATH"
  enable_cilium_clusterwide_network_policy = true

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_secondary_range_name
    services_secondary_range_name = local.services_secondary_range_name
    stack_type                    = "IPV4"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.control_plane_cidr

    master_global_access_config {
      enabled = true
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

  # Release channel & controlled maintenance schedule
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
        exclusion_name = maintenance_exclusion.key
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time

        exclusion_options {
          scope = maintenance_exclusion.value.scope
        }
      }
    }
  }

  # Security & Workload Identity for GCP service access (Pub/Sub, Cloud Storage, Cloud SQL)
  workload_identity_config {
    workload_pool = local.workload_identity_pool
  }

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

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  dynamic "secret_manager_config" {
    for_each = var.enable_secret_manager_addon ? [1] : []
    content {
      enabled = true
    }
  }

  dynamic "database_encryption" {
    for_each = var.etcd_kms_key_id != null ? [var.etcd_kms_key_id] : []
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group != null ? [var.rbac_security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # Cluster add-ons, scaling, multi-team cost attribution, and observability
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
      enabled = true
    }

    dynamic "gke_backup_agent_config" {
      for_each = var.enable_backup_for_gke ? [1] : []
      content {
        enabled = true
      }
    }

    dns_cache_config {
      enabled = true
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  cluster_autoscaling {
    autoscaling_profile = var.autoscaling_profile
  }

  cost_management_config {
    enabled = true
  }

  logging_config {
    enable_components = var.logging_components
  }

  monitoring_config {
    enable_components = var.monitoring_components

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  lifecycle {
    ignore_changes = [
      node_config,
      initial_node_count,
    ]

    precondition {
      condition     = var.node_zones == null || alltrue([for z in coalesce(var.node_zones, []) : startswith(z, "${var.region}-")])
      error_message = "Every zone in node_zones must belong to ${var.region} (e.g. '${var.region}-a')."
    }
  }

  depends_on = [
    google_project_iam_member.nodes,
    google_project_iam_member.nodes_artifact_registry,
  ]
}

# -----------------------------------------------------------------------------
# Managed GKE Standard Node Pools
# -----------------------------------------------------------------------------

resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  name_prefix       = "${trim(substr(each.key, 0, 12), "-")}-"
  project           = var.project_id
  location          = var.region
  cluster           = google_container_cluster.this.name
  node_locations    = each.value.node_zones
  max_pods_per_node = each.value.max_pods_per_node

  autoscaling {
    min_node_count  = each.value.min_nodes_per_zone
    max_node_count  = each.value.max_nodes_per_zone
    location_policy = "BALANCED"
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
        "node-pool" = each.key
      },
      each.value.labels
    )
    resource_labels = local.effective_labels
    tags            = each.value.network_tags

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

    gcfs_config {
      enabled = each.value.image_streaming
    }

    gvnic {
      enabled = each.value.enable_gvnic
    }

    linux_node_config {
      cgroup_mode = "CGROUP_MODE_V2"
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
    create_before_destroy = true

    precondition {
      condition     = each.value.node_zones == null || alltrue([for z in coalesce(each.value.node_zones, []) : startswith(z, "${var.region}-")])
      error_message = "Every zone in node_pools[\"${each.key}\"].node_zones must belong to ${var.region}."
    }
  }
}
