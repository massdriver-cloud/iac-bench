locals {
  # The network team's naming convention: one VPC per environment, one GKE
  # subnet per region, fixed secondary range names.
  network_name    = "apps-${var.environment}"
  subnetwork_name = "${local.network_name}-gke-${var.region}"

  common_labels = merge(
    {
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.labels,
  )

  # Service account IDs are limited to 30 characters; keep the suffix intact.
  node_service_account_id = "${substr("gke-${var.cluster_name}", 0, 24)}-nodes"

  # The primary pool is just another entry in the pool map so every pool gets
  # exactly the same hardening and lifecycle behaviour.
  node_pools = merge(
    {
      primary = {
        machine_type   = var.machine_type
        disk_type      = var.disk_type
        disk_size_gb   = var.disk_size_gb
        min_node_count = var.min_node_count
        max_node_count = var.max_node_count
        spot           = false
        labels         = {}
        taints         = []
      }
    },
    var.additional_node_pools,
  )
}

# ---------------------------------------------------------------------------
# Upgrade notifications: GKE publishes control plane / node upgrade events to
# this topic so the platform team can wire alerting without polling the API.
# ---------------------------------------------------------------------------

resource "google_pubsub_topic" "cluster_notifications" {
  name   = "${var.cluster_name}-gke-notifications"
  labels = local.common_labels
}

# ---------------------------------------------------------------------------
# The cluster: regional, VPC-native, private, hardened.
# ---------------------------------------------------------------------------

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region

  # Networking: the network team's VPC and regional GKE subnet, with the
  # pre-allocated secondary ranges for pods and services.
  network         = local.network_name
  subnetwork      = local.subnetwork_name
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2 (eBPF): enforced Kubernetes NetworkPolicy out of the box,
  # better observability and scale than kube-proxy/iptables.
  datapath_provider = "ADVANCED_DATAPATH"

  # Regional control plane; nodes spread across three zones by default.
  node_locations = var.node_locations

  # The module owns all node pools; the bootstrap default pool is removed.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection

  # --- Release / upgrade behaviour -----------------------------------------
  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    # 08:00 UTC is overnight in every US region; GKE picks a 4h window from
    # this start time for control plane and node maintenance.
    daily_maintenance_window {
      start_time = "08:00"
    }
  }

  notification_config {
    pubsub {
      enabled = true
      topic   = google_pubsub_topic.cluster_notifications.id
    }
  }

  # --- Control plane access --------------------------------------------------
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    # Lets connected networks (VPN/Interconnect/peering) reach the private
    # endpoint, not just resources in the cluster's own region.
    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = coalesce(cidr_blocks.value.display_name, "authorized-${cidr_blocks.key}")
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # --- Workload identity & node hardening -----------------------------------
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes       = true
  enable_intranode_visibility = true

  binary_authorization {
    evaluation_mode = var.binary_authorization_mode
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_key_name == null ? [] : [var.database_encryption_key_name]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # --- Observability & cost ---------------------------------------------------
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

  # --- Add-ons ----------------------------------------------------------------
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
      enabled = true
    }
    # NetworkPolicy enforcement is provided by Dataplane V2; the legacy
    # Calico add-on is intentionally not enabled.
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  resource_labels = local.common_labels

  lifecycle {
    precondition {
      condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
      error_message = "A public control plane endpoint requires master_authorized_networks; refusing to expose the API to 0.0.0.0/0."
    }
    precondition {
      condition     = var.min_node_count <= var.max_node_count
      error_message = "min_node_count must not exceed max_node_count."
    }
    # GKE mutates the bootstrap pool size during default-pool removal.
    ignore_changes = [initial_node_count]
  }
}
