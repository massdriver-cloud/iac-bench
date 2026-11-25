locals {
  # The GKE convention is that node pool nodes live in a pool named "<cluster>-node-pool".
  # We keep our pools unambiguously named after their role.
  system_pool_name = var.system_node_pool.name

  # The maintenance recurring_window needs a full RFC3339 timestamp. We anchor
  # the date (configuration-independent) and let the time-of-day come from the
  # variable, so only the daily start time matters to operators.
  maintenance_start_time = "1970-01-01T${var.maintenance_start_time}:00Z"
}

resource "google_container_cluster" "cluster" {
  provider = google

  name     = var.name
  project  = var.project_id
  location = var.location

  description = var.description

  network    = var.network
  subnetwork = var.subnetwork

  # A regional cluster is required for production: the control plane is
  # replicated across zones and the default node pool spans the region.
  # (location being a region + node_locations omitted => regional cluster)
  initial_node_count       = 1
  remove_default_node_pool = true
  deletion_protection      = var.deletion_protection

  enable_shielded_nodes       = var.enable_shielded_nodes
  enable_intranode_visibility = var.enable_intranode_visibility
  enable_l4_ilb_subsetting    = var.enable_l4_ilb_subsetting

  min_master_version = var.kubernetes_version

  release_channel {
    channel = var.release_channel
  }

  # VPC-native (alias IP) networking using the network team's secondary ranges.
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster: nodes have private IPs only and the master endpoint is
  # reachable from within the VPC / authorized networks.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # reachable from the VPC (and authorized networks below)
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Control-plane authorized networks are empty by default; the platform team
  # reaches the control plane over the VPC. Keeps the endpoint private.
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false
  }

  workload_identity_config {
    workload_pool = var.workload_identity_enabled ? "${var.project_id}.svc.id.goog" : null
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  cost_management_config {
    enabled = var.enable_cost_allocation
  }

  datapath_provider = var.enable_dataplane_v2 ? "ADVANCED_DATAPATH" : "DATAPATH_PROVIDER_UNSPECIFIED"

  network_policy {
    enabled  = true
    provider = var.enable_dataplane_v2 ? "PROVIDER_UNSPECIFIED" : "CALICO"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "STORAGE", "POD", "DEPLOYMENT", "STATEFULSET", "DAEMONSET", "HPA", "WORKLOADS"]
  }

  maintenance_policy {
    recurring_window {
      start_time = local.maintenance_start_time
      end_time   = "1970-01-01T23:59:00Z"
      recurrence = "FREQ=DAILY"
    }

    dynamic "maintenance_exclusion" {
      for_each = var.maintenance_exclusions
      content {
        exclusion_name = maintenance_exclusion.value.name
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time
        exclusion_options {
          scope = maintenance_exclusion.value.exclusion_scope
        }
      }
    }
  }

  resource_labels = merge(
    {
      "platform-managed" = "true"
      "environment"      = "production"
    },
    var.labels,
  )

  # Ensure the default node pool is recreated without touching control plane.
  lifecycle {
    ignore_changes = [
      node_pool,
    ]
  }
}

# ---------------------------------------------------------------------------
# System node pool
# ---------------------------------------------------------------------------

resource "google_container_node_pool" "system" {
  provider = google

  name       = local.system_pool_name
  project    = var.project_id
  location   = var.location
  cluster    = google_container_cluster.cluster.name
  node_count = var.system_node_pool.initial_node_count

  node_config {
    machine_type = var.system_node_pool.machine_type
    disk_size_gb = var.system_node_pool.disk_size_gb
    disk_type    = var.system_node_pool.disk_type
    image_type   = var.system_node_pool.image_type
    labels       = var.system_node_pool.labels

    dynamic "taint" {
      for_each = var.system_node_pool.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  autoscaling {
    min_node_count = var.system_node_pool.min_count
    max_node_count = var.system_node_pool.max_count
  }

  management {
    auto_repair  = var.system_node_pool.auto_repair
    auto_upgrade = var.system_node_pool.auto_upgrade
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 1
  }
}

# ---------------------------------------------------------------------------
# Workload node pools
# ---------------------------------------------------------------------------

resource "google_container_node_pool" "workload" {
  for_each = var.workload_node_pools

  provider = google

  name     = each.key
  project  = var.project_id
  location = var.location
  cluster  = google_container_cluster.cluster.name

  node_count = each.value.spot ? null : each.value.min_count

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = each.value.image_type
    labels       = each.value.labels
    spot         = each.value.spot

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  autoscaling {
    min_node_count = each.value.spot ? 0 : each.value.min_count
    max_node_count = each.value.spot ? 0 : each.value.max_count
  }

  management {
    auto_repair  = each.value.auto_repair
    auto_upgrade = each.value.auto_upgrade
  }

  node_locations = each.value.node_locations

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 1
  }

  depends_on = [google_container_cluster.cluster]
}