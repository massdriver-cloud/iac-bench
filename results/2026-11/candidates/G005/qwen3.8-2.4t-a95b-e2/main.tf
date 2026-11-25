# -----------------------------------------------------------------------------
# GKE Standard cluster (regional, private nodes, VPC-native).
#
# The cluster's control plane is regional, so it survives the loss of any
# single zone. Nodes live in one regional node pool (see node_pool.tf) that is
# likewise spread across all zones of the region.
# -----------------------------------------------------------------------------
resource "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  deletion_protection = var.deletion_protection

  # The throwaway default node pool is deleted immediately; the real pool is
  # managed as its own resource below (google_container_node_pool.default).
  initial_node_count       = 1
  remove_default_node_pool = true

  # --- Versioning -----------------------------------------------------------
  release_channel {
    channel = var.release_channel
  }
  min_master_version = var.kubernetes_version # null -> the release channel decides

  # --- Networking -----------------------------------------------------------
  networking_mode = "VPC_NATIVE"
  network         = var.network_name
  subnetwork      = local.subnetwork_name

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Nodes always get private IPs only. The control plane gets a private IP in
  # the VPC (reachable from within the network) and, unless
  # enable_private_endpoint is set, a public endpoint that is firewalled off
  # until master_authorized_networks is populated.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block # null -> GKE auto-assigns a /28
  }

  # Enabled unconditionally: with an empty list it denies all internet access
  # to the control plane. Product teams add their office/VPN ranges to open it.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # --- Dataplane and built-in addons -----------------------------------------
  datapath_provider        = var.datapath_provider # Dataplane V2 incl. network policy
  enable_l4_ilb_subsetting = var.enable_l4_ilb_subsetting

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    dns_cache_config {
      enabled = var.dns_cache_enabled
    }
  }

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  # --- Identity --------------------------------------------------------------
  # Workload Identity is how product workloads authenticate to Pub/Sub, Cloud
  # Storage, Cloud SQL and other Google Cloud APIs without node credentials.
  workload_identity_config {
    workload_pool = local.workload_pool
  }

  # --- Observability -----------------------------------------------------------
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  logging_config {
    enable_components = var.logging_components
  }
  monitoring_config {
    enable_components = var.monitoring_components
  }

  # --- Maintenance -------------------------------------------------------------
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
  }

  # --- Hardening -----------------------------------------------------------------
  security_posture_config {
    mode               = var.security_posture_mode
    vulnerability_mode = var.security_posture_vulnerability_mode
  }

  binary_authorization {
    evaluation_mode = var.binary_authorization_mode
  }

  # Envelope-encrypt Kubernetes Secrets with a customer-managed KMS key when
  # one is supplied; otherwise Google-managed encryption applies.
  dynamic "database_encryption" {
    for_each = var.database_encryption_key_name == null ? [] : [var.database_encryption_key_name]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # --- Notifications -----------------------------------------------------------
  dynamic "notification_config" {
    for_each = var.upgrade_notification_pubsub_topic == null ? [] : [var.upgrade_notification_pubsub_topic]
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  resource_labels = var.cluster_labels
}
