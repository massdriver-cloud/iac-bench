# ---------------------------------------------------------------------------
# Network wiring.
#
# The network team owns the VPC and subnets; this module only attaches to them.
# Naming contract:
#   VPC:    apps-<environment>
#   Subnet: apps-<environment>-gke-<region>   (secondary ranges: pods, services)
# The cluster lives in the same project as the network (var.project_id).
# ---------------------------------------------------------------------------

locals {
  network_name    = "apps-${var.environment}"
  subnetwork_name = "apps-${var.environment}-gke-${var.region}"

  common_labels = {
    environment = var.environment
    managed-by  = "opentofu"
  }

  # Least-privilege roles for the node service account. Application pods get
  # their own Google IAM identities via Workload Identity instead of inheriting
  # these; nodes only need to write telemetry and pull images.
  node_service_account_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]
}

# ---------------------------------------------------------------------------
# Dedicated node service account (never the Compute default SA, which carries
# broad project Editor permissions).
# ---------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE nodes for ${var.cluster_name} (${var.environment})"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_service_account_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# ---------------------------------------------------------------------------
# GKE Standard cluster: regional, VPC-native, private nodes, Workload Identity.
# ---------------------------------------------------------------------------

resource "google_container_cluster" "this" {
  provider = google

  name     = var.cluster_name
  project  = var.project_id
  location = var.region # regional cluster: HA control plane + nodes across all zones

  # Bring our own network; never let GKE auto-create one.
  network         = local.network_name
  subnetwork      = local.subnetwork_name
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2 (eBPF): built-in NetworkPolicy enforcement and better
  # observability, so product teams can isolate their namespaces.
  datapath_provider = "ADVANCED_DATAPATH"

  # Private nodes: no public IPs on workers; egress via Cloud NAT provided by
  # the network team. The control plane gets a private /28 endpoint.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    # Allow reaching the private control-plane endpoint from any region over
    # the VPC (peering/VPN/interconnect), not just the cluster's region.
    master_global_access_config {
      enabled = true
    }
  }

  # The public API endpoint (when enabled) is only reachable from these CIDRs.
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Workload Identity: pods authenticate to Pub/Sub, Cloud Storage, Cloud SQL,
  # etc. as their own Kubernetes service accounts - no exported SA keys.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Full telemetry so a small team can operate the cluster without extra setup.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }

    dynamic "maintenance_exclusion" {
      for_each = var.maintenance_exclusions
      content {
        exclusion_name = maintenance_exclusion.value.name
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time

        exclusion_options {
          scope = "NO_UPGRADES"
        }
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  default_max_pods_per_node = var.max_pods_per_node
  deletion_protection       = var.deletion_protection
  resource_labels           = merge(local.common_labels, var.resource_labels)

  # The GKE-created default pool is not configurable enough for production
  # (no autoscaling/surge policy); replace it with the managed pool below.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Harden even the transient default pool created during provisioning.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    image_type      = "COS_CONTAINERD"

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    # initial_node_count only sizes the removed default pool; ignore drift.
    ignore_changes = [initial_node_count]
  }

  depends_on = [google_project_iam_member.nodes]
}

# ---------------------------------------------------------------------------
# Primary node pool: autoscaled, self-healing, zero-downtime upgrades.
# ---------------------------------------------------------------------------

resource "google_container_node_pool" "primary" {
  name     = "${var.cluster_name}-primary"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.id

  # null => every zone in the region, spreading capacity for resilience.
  node_locations = var.node_locations

  autoscaling {
    min_node_count  = var.min_nodes_per_zone
    max_node_count  = var.max_nodes_per_zone
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Surge upgrades: bring up a new node before draining an old one, and never
  # take a node out of service beyond the surge - production capacity is kept.
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
    image_type   = "COS_CONTAINERD"

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(local.common_labels, var.node_labels)

    metadata = {
      disable-legacy-endpoints = "true"
    }

    # GKE metadata server hides node credentials from pods; required for
    # Workload Identity.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    precondition {
      condition     = var.max_nodes_per_zone >= var.min_nodes_per_zone
      error_message = "max_nodes_per_zone must be >= min_nodes_per_zone."
    }

    # Node count is owned by the cluster autoscaler after creation.
    ignore_changes = [initial_node_count]
  }
}
