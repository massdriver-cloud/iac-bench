# ---------------------------------------------------------------------------
# GKE Standard module — production clusters for the platform team.
#
# Design decisions owned by this module:
#   * Regional cluster (control plane + nodes spread across the region's
#     zones) so a zone outage does not take the cluster down.
#   * VPC-native networking on the network team's pre-existing subnetwork,
#     using its "pods" / "services" secondary ranges.
#   * Private nodes; the control plane endpoint is public by default but can
#     be restricted (master_authorized_networks) or made fully private
#     (enable_private_endpoint).
#   * Dataplane V2 (eBPF): enforces Kubernetes NetworkPolicies cluster-wide
#     without the legacy Calico addon — important on multi-team clusters.
#   * Workload Identity Federation for GKE, so product teams reach
#     Pub/Sub / Cloud Storage / Cloud SQL from pods via Google service
#     accounts — no exported service-account keys.
#   * Nodes run a dedicated, least-privilege service account (not the default
#     Compute Engine account) on shielded, secure-boot VMs with image
#     streaming; auto-repair and auto-upgrade are on.
#   * Node pools are managed as separate resources (the provider default pool
#     is removed) and are autoscaled with surge upgrades.
#   * Release-channel upgrades confined to a maintenance window, system +
#     workload logging, Managed Service for Prometheus, NodeLocal DNSCache,
#     and per-cluster cost metering.
# ---------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region
}

# Used only to resolve the effective project when var.project_id is null.
data "google_project" "this" {}

locals {
  project_id = coalesce(var.project_id, data.google_project.this.project_id)

  # Network-team naming convention: one GKE subnetwork per VPC per region.
  subnetwork_name = coalesce(var.subnetwork, "${var.network}-gke-${var.region}")

  secondary_range_names = [
    for range in data.google_compute_subnetwork.gke.secondary_ip_range : range.range_name
  ]

  # Minimal roles for node service accounts. Anything a workload needs beyond
  # this should go through Workload Identity, not the node identity.
  node_service_account_roles = toset(concat([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ], var.node_service_account_extra_roles))
}

# --- Existing network infrastructure, owned by the network team -------------

data "google_compute_network" "vpc" {
  project = local.project_id
  name    = var.network
}

data "google_compute_subnetwork" "gke" {
  project = local.project_id
  region  = var.region
  name    = local.subnetwork_name
}

# --- Node identity -----------------------------------------------------------

resource "google_service_account" "nodes" {
  project      = local.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes — cluster ${var.name}"
  description  = "Least-privilege identity for the nodes of the ${var.name} GKE cluster. Managed by OpenTofu; workloads should use Workload Identity instead."
}

resource "google_project_iam_member" "node_service_account" {
  for_each = local.node_service_account_roles

  project = local.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# --- Cluster -----------------------------------------------------------------

resource "google_container_cluster" "this" {
  name        = var.name
  description = "Shared production cluster managed by the platform team's OpenTofu module."
  project     = local.project_id
  location    = var.region # regional cluster: control plane in every zone of the region

  network    = data.google_compute_network.vpc.id
  subnetwork = data.google_compute_subnetwork.gke.id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Nodes are managed exclusively through google_container_node_pool below.
  remove_default_node_pool = true
  initial_node_count       = 1

  min_master_version = var.kubernetes_version
  release_channel {
    channel = var.release_channel
  }

  # eBPF data plane: built-in NetworkPolicy enforcement for tenant isolation.
  datapath_provider = "ADVANCED_DATAPATH"

  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
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

  # Workload Identity Federation for GKE — how pods authenticate to Pub/Sub,
  # Cloud Storage, Cloud SQL, etc. without service-account keys.
  workload_identity_config {
    workload_pool = "${local.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    # Node-local DNS cache: removes a common latency/failure point at scale.
    dns_cache_config {
      enabled = true
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = var.maintenance_recurrence
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.authenticator_security_group != null ? [1] : []
    content {
      security_group = var.authenticator_security_group
    }
  }

  dynamic "notification_config" {
    for_each = var.upgrade_notification_topic != null ? [1] : []
    content {
      pubsub {
        enabled = true
        topic   = var.upgrade_notification_topic
      }
    }
  }

  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  # Per-cluster usage metering: the basis for showback across product teams.
  cost_management_config {
    enabled = true
  }

  resource_labels = var.labels

  deletion_protection = var.deletion_protection

  lifecycle {
    precondition {
      condition     = contains(local.secondary_range_names, var.pods_secondary_range_name)
      error_message = "Subnetwork \"${local.subnetwork_name}\" has no secondary range named \"${var.pods_secondary_range_name}\" — the network team must provide it for pod IPs."
    }
    precondition {
      condition     = contains(local.secondary_range_names, var.services_secondary_range_name)
      error_message = "Subnetwork \"${local.subnetwork_name}\" has no secondary range named \"${var.services_secondary_range_name}\" — the network team must provide it for service IPs."
    }
  }

  timeouts {
    create = "45m"
    update = "60m"
    delete = "45m"
  }
}

# --- Node pools --------------------------------------------------------------

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  project  = local.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  node_locations = each.value.node_locations

  # Fixed size (per zone) only when autoscaling is off.
  node_count = each.value.autoscaling ? null : each.value.node_count

  dynamic "autoscaling" {
    for_each = each.value.autoscaling ? [each.value] : []
    content {
      min_node_count  = autoscaling.value.min_count
      max_node_count  = autoscaling.value.max_count
      location_policy = "BALANCED" # spread nodes evenly across zones
    }
  }

  management {
    auto_repair  = each.value.auto_repair
    auto_upgrade = each.value.auto_upgrade
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    machine_type = each.value.machine_type
    image_type   = each.value.image_type
    disk_type    = each.value.disk_type
    disk_size_gb = each.value.disk_size_gb
    spot         = each.value.spot

    service_account = google_service_account.nodes.email
    # Full API scope is safe here because access is bounded by the
    # least-privilege IAM roles on the dedicated node service account.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = each.value.labels
    tags   = each.value.tags

    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Serves pod identity from the GKE metadata server (Workload Identity).
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }

    # Image streaming for faster, more predictable pod starts.
    gcfs_config {
      enabled = true
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

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}
