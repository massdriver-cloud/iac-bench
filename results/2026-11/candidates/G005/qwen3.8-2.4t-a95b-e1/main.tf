# ---------------------------------------------------------------------------
# GKE Standard control plane — regional for availability, private for security.
# Autopilot is deliberately not enabled: this module provisions GKE Standard
# clusters only.
# ---------------------------------------------------------------------------

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  network    = local.network_url
  subnetwork = local.subnetwork_url

  # --- Versioning: ride the release channel instead of pinning versions. ----
  release_channel {
    channel = var.release_channel
  }
  min_master_version = var.kubernetes_version

  # --- Networking: use the secondary ranges the network team created. ------
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = var.enable_master_global_access
    }
  }

  # Always present, even when empty: if the public endpoint is ever enabled,
  # it is restricted to these CIDRs instead of being open to the world.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        display_name = cidr_blocks.value.display_name
        cidr_block   = cidr_blocks.value.cidr_block
      }
    }
  }

  # Dataplane V2: eBPF-based datapath with built-in NetworkPolicy enforcement.
  datapath_provider = "ADVANCED_DATAPATH"

  # Lets product teams create internal L4 load balancers without extra config.
  enable_l4_ilb_subsetting = true

  # --- Security posture. ----------------------------------------------------
  enable_shielded_nodes = true

  workload_identity_config {
    workload_pool = local.workload_pool
  }

  dynamic "database_encryption" {
    for_each = var.secrets_kms_key != null ? [var.secrets_kms_key] : []
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # --- Observability and cost visibility. -----------------------------------
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = true
    }
  }

  cost_management_config {
    enabled = true
  }

  # --- Addons product teams expect in a shared production cluster. ----------
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

    # Workloads use Cloud Storage; GCS FUSE lets them mount buckets directly.
    gcs_fuse_csi_driver_config {
      enabled = true
    }
  }

  # --- Maintenance: weekend window (UTC), outside business hours. -----------
  maintenance_policy {
    recurring_window {
      start_time = "2000-01-01T${var.maintenance_window.start_time}:00Z"
      end_time   = "2000-01-01T${var.maintenance_window.end_time}:00Z"
      recurrence = local.maintenance_recurrence
    }
  }

  # --- Node management: capacity is owned by google_container_node_pool. ----
  remove_default_node_pool = true
  initial_node_count       = 1

  resource_labels = var.resource_labels

  deletion_protection = var.deletion_protection

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]

    precondition {
      condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
      error_message = "Refusing to expose the control plane publicly with no authorized networks: keep enable_private_endpoint = true, or provide at least one master_authorized_networks entry."
    }
  }
}
