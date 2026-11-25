resource "google_container_cluster" "this" {
  project     = local.project_id
  name        = var.name
  description = "${var.environment} cluster shared by product teams. Managed by OpenTofu."

  # Regional: control plane replicated across zones, nodes spread over the region's zones.
  location = var.region

  deletion_protection = var.deletion_protection
  resource_labels     = local.labels

  ###########################################################################
  # Network: the network team's VPC and GKE subnet, VPC-native
  ###########################################################################

  network           = local.network
  subnetwork        = local.subnetwork
  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH" # Dataplane V2: NetworkPolicy is enforced, teams can isolate namespaces

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }

  ###########################################################################
  # Control plane and node exposure
  #
  # - Nodes have internal IPs only.
  # - The control plane has no public IP endpoint. Its private endpoint is
  #   reachable from the cluster subnet and the listed internal ranges.
  # - People and CI connect through the DNS-based endpoint, where every
  #   request is authenticated and authorized by IAM.
  ###########################################################################

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true

    master_global_access_config {
      enabled = true # private endpoint usable from the VPC's other regions (still limited to authorized ranges)
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.control_plane_authorized_networks
      content {
        display_name = cidr_blocks.value.name
        cidr_block   = cidr_blocks.value.cidr_block
      }
    }
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = var.control_plane_dns_endpoint_external_access
    }
  }

  ###########################################################################
  # Identity and access
  ###########################################################################

  # Workloads reach Pub/Sub, Cloud Storage, Cloud SQL etc. as their own
  # Kubernetes service account identity. No service account keys.
  workload_identity_config {
    workload_pool = "${local.project_id}.svc.id.goog"
  }

  enable_legacy_abac = false

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group == null ? [] : [var.rbac_security_group]
    content {
      security_group = authenticator_groups_config.value
    }
  }

  ###########################################################################
  # Hardening
  ###########################################################################

  enable_shielded_nodes = true

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_DISABLED"
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  dynamic "database_encryption" {
    for_each = var.secrets_encryption_kms_key == null ? [] : [var.secrets_encryption_kms_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  node_pool_defaults {
    node_config_defaults {
      insecure_kubelet_readonly_port_enabled = "FALSE"
    }
  }

  ###########################################################################
  # Upgrades and maintenance
  ###########################################################################

  release_channel {
    channel = local.release_channel
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

  ###########################################################################
  # Add-ons and operations
  ###########################################################################

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
    dns_cache_config {
      enabled = true # NodeLocal DNSCache: DNS keeps working through kube-dns hiccups
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  # Per-namespace / per-label cost breakdown in Cloud Billing, for a cluster shared by several teams.
  cost_management_config {
    enabled = true
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
      "STORAGE",
      "HPA",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
      "STATEFULSET",
      "KUBELET",
      "CADVISOR",
    ]

    managed_prometheus {
      enabled = true
    }
  }

  ###########################################################################
  # Node pools are separate resources (node_pools.tf). GKE insists on creating
  # a default pool with the cluster; it is created with the hardened node
  # identity and removed straight away.
  ###########################################################################

  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    # The default pool no longer exists after creation; never let its settings force a cluster replacement.
    ignore_changes = [node_config, initial_node_count]
  }

  depends_on = [
    google_project_service.container,
    google_project_iam_member.nodes,
  ]
}
