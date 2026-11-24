resource "google_container_cluster" "this" {
  name        = var.cluster_name
  project     = var.project_id
  location    = var.region
  description = "Managed GKE Standard ${var.environment} cluster (${var.region})"

  node_locations      = length(var.node_zones) > 0 ? var.node_zones : null
  resource_labels     = local.common_labels
  deletion_protection = local.deletion_protection

  # Create the cluster with no default node pool (supported directly on GKE 1.36.4+,
  # replacing the deprecated remove_default_node_pool flag). All nodes are managed
  # via dedicated google_container_node_pool resources in node_pools.tf.
  initial_node_count = 0

  ##############################################################################
  # Networking: VPC-Native, Dataplane V2 (eBPF), Private Nodes
  ##############################################################################

  network                   = data.google_compute_network.vpc.id
  subnetwork                = data.google_compute_subnetwork.gke.id
  networking_mode           = "VPC_NATIVE"
  datapath_provider         = "ADVANCED_DATAPATH"
  default_max_pods_per_node = var.default_max_pods_per_node

  enable_intranode_visibility              = var.enable_intranode_visibility
  enable_cilium_clusterwide_network_policy = var.enable_cilium_clusterwide_network_policy
  enable_fqdn_network_policy               = var.enable_fqdn_network_policy
  enable_l4_ilb_subsetting                 = true

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
    stack_type                    = "IPV4"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    # Allow clients in other US regions of the same VPC to reach the private endpoint.
    master_global_access_config {
      enabled = true
    }
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = var.enable_dns_endpoint_external_traffic
    }
    ip_endpoints_config {
      enabled = true
    }
  }

  # Fail closed: public internet access to the API server is blocked unless
  # CIDRs are explicitly added to var.authorized_networks.
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled      = false
    private_endpoint_enforcement_enabled = var.enforce_authorized_networks_on_private_endpoint

    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  ##############################################################################
  # Security, Identity & Multi-Team Isolation
  ##############################################################################

  # Workload Identity Federation lets product team pods authenticate to Pub/Sub,
  # Cloud Storage, Cloud SQL, and Secret Manager using per-KSA IAM bindings
  # with zero static JSON keys.
  workload_identity_config {
    workload_pool = local.workload_pool
  }

  enable_shielded_nodes = true
  enable_legacy_abac    = false

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Harden Kubernetes API authentication and prevent multi-team privilege mistakes.
  anonymous_authentication_config {
    mode = "LIMITED"
  }

  rbac_binding_config {
    enable_insecure_binding_system_unauthenticated = false
    enable_insecure_binding_system_authenticated   = false
  }

  # Block Service.spec.externalIPs to mitigate CVE-2020-8554 traffic hijacking
  # across product teams sharing the cluster.
  service_external_ips_config {
    enabled = false
  }

  dynamic "authenticator_groups_config" {
    for_each = var.security_group != null ? [var.security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_kms_key_id != null ? [var.database_encryption_kms_key_id] : []
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
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

  ##############################################################################
  # Lifecycle, Autoscaling, Maintenance & Cost Visibility
  ##############################################################################

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

  # Disable Node Auto-Provisioning so all node pools stay explicitly governed in
  # OpenTofu while tuning the Cluster Autoscaler scheduling profile.
  cluster_autoscaling {
    enabled             = false
    autoscaling_profile = var.autoscaling_profile
  }

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  cost_management_config {
    enabled = var.enable_cost_allocation
  }

  dynamic "notification_config" {
    for_each = var.notification_pubsub_topic != null ? [var.notification_pubsub_topic] : []
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
        filter {
          event_type = [
            "UPGRADE_AVAILABLE_EVENT",
            "UPGRADE_EVENT",
            "SECURITY_BULLETIN_EVENT",
          ]
        }
      }
    }
  }

  ##############################################################################
  # Observability: Cloud Logging, Cloud Monitoring & Managed Prometheus
  ##############################################################################

  logging_config {
    enable_components = var.logging_components
  }

  monitoring_config {
    enable_components = var.monitoring_components

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  ##############################################################################
  # Kubernetes Add-ons & Storage
  ##############################################################################

  gateway_api_config {
    channel = var.gateway_api_channel
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    gce_persistent_disk_csi_driver_config {
      enabled = var.enable_gce_pd_csi_driver
    }

    gcs_fuse_csi_driver_config {
      enabled = var.enable_gcs_fuse_csi_driver
    }

    dns_cache_config {
      enabled = var.enable_dns_cache
    }
  }

  depends_on = [
    google_kms_crypto_key_iam_member.etcd_cmek,
  ]
}
