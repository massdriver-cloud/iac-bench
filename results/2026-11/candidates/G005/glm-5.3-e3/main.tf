# ---------------------------------------------------------------------------
# GKE Standard cluster (production)
#
# This module is applied once per cluster. It assumes the network team's VPC
# and its '<vpc>-gke-<region>' subnet (with the 'pods' and 'services'
# secondary ranges) already exist in the same project.
# ---------------------------------------------------------------------------

locals {
  # Standard naming: clusters are '<vpc>-<region>' on '<vpc>-gke-<region>'
  # subnets, unless an engineer explicitly overrides either name.
  cluster_name = coalesce(var.cluster_name, "${var.vpc_name}-${var.region}")
  subnet_name  = coalesce(var.subnet_name, "${var.vpc_name}-gke-${var.region}")

  network    = "projects/${var.project_id}/global/networks/${var.vpc_name}"
  subnetwork = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  # Workload Identity pool: Kubernetes service accounts in this cluster can
  # be bound to Google Cloud IAM (Pub/Sub, Cloud Storage, Cloud SQL, ...) and
  # never need node credentials to reach other services.
  workload_identity_pool = "${var.project_id}.svc.id.goog"

  # Nodes run on a dedicated service account, never on the Compute Engine
  # default service account: either the module creates one, or the engineer
  # points at an existing account via node_service_account_email. Leaving
  # both unset makes the node pools fail their precondition at plan time.
  node_service_account_email = var.create_node_service_account ? one(google_service_account.nodes[*].email) : var.node_service_account_email
  node_service_account_roles = var.create_node_service_account ? var.node_service_account_roles : []
}

resource "google_container_cluster" "this" {
  name     = local.cluster_name
  location = var.region # regional: the control plane survives a zone failure
  project  = var.project_id

  # VPC-native networking: pod IPs and Service ClusterIPs come from the
  # network team's secondary ranges on the GKE subnet.
  network    = local.network
  subnetwork = local.subnetwork

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Nodes are private (no external IP addresses). The control plane endpoint
  # is private by default and is reached from inside the VPC (jump host, VPN
  # or Interconnect) plus any ranges in master_authorized_networks.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.control_plane_ipv4_cidr
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [true] : []

    content {
      dynamic "cidr_blocks" {
        for_each = { for index, cidr in var.master_authorized_networks : index => cidr }

        content {
          cidr_block   = cidr_blocks.value
          display_name = "authorized-${cidr_blocks.key}"
        }
      }
    }
  }

  # Access is via Google identities (gke-gcloud-auth-plugin), so no static
  # client certificates are issued.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # GKE manages versions: the REGULAR channel delivers tested Kubernetes
  # versions on a predictable cadence, and control-plane upgrades land inside
  # the daily maintenance window below.
  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  # Dataplane V2 (eBPF) with network policy enforcement: the foundation for
  # isolating product teams' workloads from each other on a shared cluster.
  datapath_provider = "ADVANCED_DATAPATH"

  network_policy {
    enabled = true
  }

  enable_intranode_visibility = true
  enable_shielded_nodes       = true

  workload_identity_config {
    workload_pool = local.workload_identity_pool
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = true
    }
  }

  # Optional: recognise a Cloud Identity group for RBAC group bindings.
  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group != null ? [var.rbac_security_group] : []

    content {
      security_group = authenticator_groups_config.value
    }
  }

  # Optional: application-layer encryption of Kubernetes Secrets with CMEK.
  dynamic "database_encryption" {
    for_each = var.database_encryption_key_name != null ? [var.database_encryption_key_name] : []

    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # All nodes live in the module-managed pools below; the throwaway default
  # pool is deleted immediately after cluster creation.
  initial_node_count       = 1
  remove_default_node_pool = true

  resource_labels = var.labels

  # Production clusters must not be destroyed by accident.
  deletion_protection = var.deletion_protection

  lifecycle {
    precondition {
      condition     = length(local.cluster_name) <= 40
      error_message = "Cluster names are limited to 40 characters: shorten cluster_name (or the '<vpc>-<region>' default name)."
    }

    precondition {
      condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
      error_message = "Refusing to create a control plane endpoint reachable from the entire internet: keep enable_private_endpoint = true, or list the CIDR blocks allowed to reach it in master_authorized_networks."
    }
  }
}

# ---------------------------------------------------------------------------
# Node pools
#
# Every pool the module creates gets the same production treatment:
# autoscaling, auto-repair, auto-upgrade, surge upgrades, containerd COS
# image, Secure Boot, GKE_METADATA mode and the dedicated node service
# account. In regional clusters min/max node counts apply per zone.
# ---------------------------------------------------------------------------

# The 'system' pool hosts GKE system components and observability agents so
# they never compete with product workloads for capacity.
resource "google_container_node_pool" "system" {
  count = var.create_system_node_pool ? 1 : 0

  name     = "system"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.id

  autoscaling {
    min_node_count = var.system_node_pool_min_size
    max_node_count = var.system_node_pool_max_size
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.system_node_pool_machine_type
    disk_size_gb = 50
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"

    labels = {
      dedicated = "system"
    }

    service_account = local.node_service_account_email
    oauth_scopes    = var.node_oauth_scopes

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Nodes never expose the metadata needed to impersonate the node service
    # account; pods use Workload Identity instead.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    precondition {
      condition     = var.system_node_pool_min_size <= var.system_node_pool_max_size
      error_message = "system_node_pool_min_size must not exceed system_node_pool_max_size."
    }

    precondition {
      condition     = local.node_service_account_email != null
      error_message = "GKE nodes must not run on the Compute Engine default service account: keep create_node_service_account = true or set node_service_account_email."
    }
  }
}

# Product-team workload pools. Use taints to dedicate a pool, min_size 0 for
# pools that may scale to zero (for example Spot pools).
resource "google_container_node_pool" "workload" {
  for_each = { for pool in var.node_pools : pool.name => pool }

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.id

  autoscaling {
    min_node_count = coalesce(each.value.min_size, 1)
    max_node_count = coalesce(each.value.max_size, 3)
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = coalesce(each.value.disk_size_gb, 100)
    disk_type    = coalesce(each.value.disk_type, "pd-balanced")
    image_type   = "COS_CONTAINERD"

    labels = each.value.labels == null ? {} : each.value.labels
    tags   = each.value.tags == null ? [] : each.value.tags

    dynamic "taint" {
      for_each = each.value.taints == null ? [] : each.value.taints

      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    spot = coalesce(each.value.spot, false)

    service_account = local.node_service_account_email
    oauth_scopes    = var.node_oauth_scopes

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    precondition {
      condition     = local.node_service_account_email != null
      error_message = "GKE nodes must not run on the Compute Engine default service account: keep create_node_service_account = true or set node_service_account_email."
    }
  }
}

# ---------------------------------------------------------------------------
# Node identity
# ---------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  count = var.create_node_service_account ? 1 : 0

  project = var.project_id

  # Deterministic, per-cluster name that fits the 30-character service
  # account limit even for long cluster names; the hash suffix keeps
  # different clusters from colliding.
  account_id   = format("gke-%s-%s", substr(local.cluster_name, 0, 20), substr(sha256(local.cluster_name), 0, 5))
  display_name = "GKE nodes: ${local.cluster_name}"
  description  = "Node service account for the ${local.cluster_name} GKE cluster, created by the standard GKE module."
}

# Additive (non-authoritative) bindings, so other tooling can grant this
# service account additional roles without fights over project IAM policy.
resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_service_account_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.node_service_account_email}"
}
