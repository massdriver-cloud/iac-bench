resource "google_container_cluster" "this" {
  project     = var.project_id
  name        = var.name
  description = "Shared GKE Standard cluster (${var.environment}) in ${var.region}"
  location    = var.region

  node_locations      = length(var.node_locations) > 0 ? var.node_locations : null
  min_master_version  = var.min_master_version
  deletion_protection = var.deletion_protection

  # GKE Standard managed via dedicated google_container_node_pool resources.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Shared environment VPC & pre-provisioned regional subnet (<vpc>-gke-<region>)
  networking_mode = "VPC_NATIVE"
  network         = local.network_self_link
  subnetwork      = local.subnetwork_self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Dataplane V2 provides eBPF/Cilium datapath, native Kubernetes NetworkPolicy
  # enforcement for multi-team isolation, and built-in intra-node visibility.
  datapath_provider                        = "ADVANCED_DATAPATH"
  enable_cilium_clusterwide_network_policy = var.enable_cilium_clusterwide_network_policy
  enable_shielded_nodes                    = true
  enable_legacy_abac                       = false
  resource_labels                          = local.common_labels

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

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

  anonymous_authentication_config {
    mode = "LIMITED"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  release_channel {
    channel = var.release_channel
  }

  workload_identity_config {
    workload_pool = local.workload_identity_pool
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
  }

  gateway_api_config {
    channel = var.enable_gateway_api ? "CHANNEL_STANDARD" : "CHANNEL_DISABLED"
  }

  secret_manager_config {
    enabled = var.enable_secret_manager_addon
  }

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  cost_management_config {
    enabled = var.enable_cost_allocation
  }

  security_posture_config {
    mode               = var.security_posture_mode
    vulnerability_mode = var.security_posture_vulnerability_mode
  }

  binary_authorization {
    evaluation_mode = var.binary_authorization_evaluation_mode
  }

  database_encryption {
    state    = var.database_encryption_key_name != null ? "ENCRYPTED" : "DECRYPTED"
    key_name = var.database_encryption_key_name
  }

  dynamic "authenticator_groups_config" {
    for_each = var.authenticator_security_group != null ? [var.authenticator_security_group] : []
    content {
      security_group = authenticator_groups_config.value
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

    advanced_datapath_observability_config {
      enable_metrics = var.enable_dataplane_v2_observability
      enable_relay   = var.enable_dataplane_v2_observability
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_recurring_window.start_time
      end_time   = var.maintenance_recurring_window.end_time
      recurrence = var.maintenance_recurring_window.recurrence
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

  # Hardened bootstrap node_config used only for the temporary 1-node default pool
  # during ClusterCreate before remove_default_node_pool deletes it, satisfying
  # organization policies that forbid the default Compute Engine SA or unshielded VMs.
  node_config {
    service_account   = google_service_account.nodes.email
    oauth_scopes      = ["https://www.googleapis.com/auth/cloud-platform"]
    disk_type         = "pd-balanced"
    disk_size_gb      = 50
    boot_disk_kms_key = var.boot_disk_kms_key

    metadata = {
      "disable-legacy-endpoints" = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  depends_on = [
    google_project_iam_member.nodes,
  ]

  lifecycle {
    ignore_changes = [
      node_config,
      initial_node_count,
    ]

    precondition {
      condition     = alltrue([for z in var.node_locations : startswith(z, "${var.region}-")])
      error_message = "Every zone in node_locations must belong to var.region (${var.region})."
    }

    precondition {
      condition     = var.system_node_pool.enabled || length(var.node_pools) > 0
      error_message = "At least one node pool must be configured (enable system_node_pool or define at least one entry in node_pools)."
    }
  }
}
