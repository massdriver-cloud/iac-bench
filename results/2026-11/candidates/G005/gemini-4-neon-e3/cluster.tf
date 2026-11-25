resource "google_container_cluster" "this" {
  name                = var.cluster_name
  project             = local.project_id
  location            = var.region
  node_locations      = length(var.node_locations) > 0 ? var.node_locations : null
  description         = var.cluster_description
  deletion_protection = var.deletion_protection
  resource_labels     = local.common_labels

  # GKE Standard best practice: remove the unmanaged default node pool immediately
  # and manage all node pools explicitly via google_container_node_pool resources.
  remove_default_node_pool = true
  initial_node_count       = 1

  # VPC-native networking using the network team's pre-provisioned VPC and regional subnet.
  network                                  = data.google_compute_network.vpc.self_link
  subnetwork                               = data.google_compute_subnetwork.subnet.self_link
  networking_mode                          = "VPC_NATIVE"
  datapath_provider                        = "ADVANCED_DATAPATH"
  enable_cilium_clusterwide_network_policy = true
  enable_intranode_visibility              = true
  enable_l4_ilb_subsetting                 = true
  default_max_pods_per_node                = var.default_max_pods_per_node

  # Hardened cluster-wide security defaults.
  enable_shielded_nodes = true
  enable_legacy_abac    = false

  anonymous_authentication_config {
    mode = "LIMITED"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
    stack_type                    = "IPV4"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = local.master_ipv4_cidr_block

    master_global_access_config {
      enabled = var.enable_master_global_access
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled      = var.enable_private_endpoint ? false : var.gcp_public_cidrs_access_enabled
    private_endpoint_enforcement_enabled = var.enable_private_endpoint

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Workload Identity Federation enables workloads to authenticate directly to
  # Pub/Sub, Cloud Storage, Cloud SQL, and Secret Manager with least privilege.
  workload_identity_config {
    workload_pool = local.workload_identity_pool
  }

  dynamic "authenticator_groups_config" {
    for_each = var.security_group != null ? [var.security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  database_encryption {
    state    = var.database_encryption_key_name != null ? "ENCRYPTED" : "DECRYPTED"
    key_name = var.database_encryption_key_name
  }

  binary_authorization {
    evaluation_mode = var.binary_authorization_mode
  }

  security_posture_config {
    mode               = var.security_posture_mode
    vulnerability_mode = var.vulnerability_scanning_mode
  }

  secret_manager_config {
    enabled = var.enable_secret_manager_addon
  }

  # Multi-tenant cost attribution by Kubernetes namespace and label in Cloud Billing.
  cost_management_config {
    enabled = true
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
        exclusion_name = maintenance_exclusion.value.exclusion_name
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time
        exclusion_options {
          scope = maintenance_exclusion.value.scope
        }
      }
    }
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

  node_pool_defaults {
    node_config_defaults {
      logging_variant = var.logging_variant
    }
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    dns_cache_config {
      enabled = true
    }

    gce_persistent_disk_csi_driver_config {
      enabled = true
    }

    gcs_fuse_csi_driver_config {
      enabled = var.enable_gcs_fuse_csi_driver
    }

    gcp_filestore_csi_driver_config {
      enabled = var.enable_filestore_csi_driver
    }

    gke_backup_agent_config {
      enabled = var.enable_backup_agent
    }
  }

  dynamic "notification_config" {
    for_each = var.notification_topic_id != null ? [var.notification_topic_id] : []
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  # Hardened configuration for the ephemeral bootstrap node pool before removal.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"

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

  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_config,
    ]

    precondition {
      condition     = contains(local.subnet_secondary_range_names, local.pods_range_name)
      error_message = "Subnet ${local.subnet_name} in ${var.region} must define a secondary IP range named \"${local.pods_range_name}\"."
    }

    precondition {
      condition     = contains(local.subnet_secondary_range_names, local.services_range_name)
      error_message = "Subnet ${local.subnet_name} in ${var.region} must define a secondary IP range named \"${local.services_range_name}\"."
    }

    precondition {
      condition     = data.google_compute_subnetwork.subnet.private_ip_google_access
      error_message = "Subnet ${local.subnet_name} in ${var.region} must have Private Google Access enabled for private GKE nodes to reach Google Cloud APIs."
    }
  }

  depends_on = [
    google_project_iam_member.node_default,
    google_project_iam_member.node_artifact_registry_reader,
  ]
}
