locals {
  # `network` may be a plain name or a full self-link; derive the short name
  # so the subnetwork naming convention works in both cases.
  network_short_name = element(reverse(split("/", var.network)), 0)

  # Network team convention: one GKE subnetwork per region named
  # "<vpc>-gke-<region>" with secondary ranges "pods" and "services".
  subnetwork = coalesce(var.subnetwork, "${local.network_short_name}-gke-${var.region}")

  # Every cluster in a VPC needs its own control-plane peering range.
  needs_master_cidr = var.enable_private_nodes || var.enable_private_endpoint
}

# ------------------------------------------------------------------------------
# Regional GKE Standard cluster.
#
# Design decisions baked in (see README.md for rationale):
#  - regional control plane + nodes spread across all zones of the region
#  - VPC-native (alias IPs) on the network team's existing subnetwork
#  - Dataplane V2 (eBPF): built-in network policy enforcement and observability
#  - Workload Identity Federation for GKE: workloads reach Pub/Sub, Cloud
#    Storage, Cloud SQL, etc. with Kubernetes service accounts, never node keys
#  - private nodes by default; control-plane access locked down by the caller
#  - no legacy client certificates; no Service externalIPs; shielded nodes
#  - release-channel upgrades inside a daily maintenance window
# ------------------------------------------------------------------------------
resource "google_container_cluster" "this" {
  name        = var.cluster_name
  description = "Production GKE Standard cluster managed by the platform team (OpenTofu)."
  project     = var.project_id
  location    = var.region

  network         = var.network
  subnetwork      = local.subnetwork
  networking_mode = "VPC_NATIVE"

  # Dataplane V2 (eBPF) datapath: native network policy enforcement and
  # flow observability without running a Calico add-on.
  datapath_provider = "ADVANCED_DATAPATH"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Node pools are managed as dedicated google_container_node_pool resources.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection

  release_channel {
    channel = var.release_channel
  }

  # Regional clusters default to all zones of the region.
  node_locations = length(var.node_locations) > 0 ? var.node_locations : null

  resource_labels = var.labels

  # ---- Identity and access ------------------------------------------------
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group != null ? [var.rbac_security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # ---- Security hardening -------------------------------------------------
  enable_shielded_nodes = true

  # Unauthenticated requests are limited to a small set of health endpoints.
  anonymous_authentication_config {
    mode = "LIMITED"
  }

  service_external_ips_config {
    enabled = false
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_key != null ? [var.database_encryption_key] : []
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # ---- Private cluster ----------------------------------------------------
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = local.needs_master_cidr ? var.master_ipv4_cidr : null

    master_global_access_config {
      enabled = var.enable_private_endpoint
    }
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [true] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # ---- Add-ons ------------------------------------------------------------
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
    gke_backup_agent_config {
      enabled = var.enable_backup_agent
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # ---- Operations ---------------------------------------------------------
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  logging_config {
    enable_components = var.logging_enabled_components
  }

  monitoring_config {
    enable_components = var.monitoring_enabled_components

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  cost_management_config {
    enabled = var.enable_cost_allocation
  }

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  # All cluster notification event types (upgrades available/in progress,
  # security bulletins) are published to the topic; consumers filter.
  dynamic "notification_config" {
    for_each = var.enable_upgrade_notifications ? [true] : []
    content {
      pubsub {
        enabled = true
        topic   = google_pubsub_topic.upgrade_notifications[0].id
      }
    }
  }

  timeouts {
    create = "45m"
    update = "60m"
    delete = "45m"
  }
}
