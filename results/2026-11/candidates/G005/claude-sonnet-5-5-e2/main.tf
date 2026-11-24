locals {
  vpc_name        = "apps-${var.environment}"
  subnetwork_name = "${local.vpc_name}-gke-${var.region}"

  network    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnetwork_name}"

  labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  node_sa_roles = toset(concat([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ], var.node_service_account_extra_roles))
}

# Dedicated, least-privilege identity for nodes (never the default Compute SA).
# Workloads reach Pub/Sub, Cloud Storage, Cloud SQL, etc. through Workload
# Identity Federation for GKE, not through this account.
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes for ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = local.node_sa_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  provider = google

  project  = var.project_id
  name     = var.name
  location = var.region # regional: control plane replicated across 3 zones

  node_locations = var.node_locations

  network    = local.network
  subnetwork = local.subnetwork

  # Node pools are managed separately.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection
  resource_labels     = local.labels

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # eBPF dataplane; also provides enforcement of Kubernetes NetworkPolicy so
  # teams sharing the cluster can isolate their namespaces.
  datapath_provider = "ADVANCED_DATAPATH"

  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
  }

  # Private nodes (no external IPs); API reachable only from the listed CIDRs.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

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

  # Workload Identity: pods authenticate to Google APIs as their own
  # Kubernetes service account (per-team / per-workload least privilege).
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_kms_key == null ? [] : [1]
    content {
      state    = "ENCRYPTED"
      key_name = var.database_encryption_kms_key
    }
  }

  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # No basic auth / client certificates are issued (provider defaults), and
  # legacy ABAC is disabled.
  enable_legacy_abac = false

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER"]
    managed_prometheus {
      enabled = true
    }
  }

  cost_management_config {
    enabled = true
  }

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
      enabled = true
    }
    gke_backup_agent_config {
      enabled = true
    }
  }

  lifecycle {
    precondition {
      condition     = var.node_locations == null || alltrue([for z in var.node_locations : startswith(z, "${var.region}-")])
      error_message = "node_locations must all be zones inside var.region."
    }
  }

  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "default" {
  project  = var.project_id
  name     = "default"
  cluster  = google_container_cluster.this.name
  location = var.region

  # Per-zone counts, scaled by the cluster autoscaler.
  initial_node_count = var.node_pool.min_node_count

  autoscaling {
    min_node_count  = var.node_pool.min_node_count
    max_node_count  = var.node_pool.max_node_count
    location_policy = "BALANCED"
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
    machine_type    = var.node_pool.machine_type
    disk_size_gb    = var.node_pool.disk_size_gb
    disk_type       = var.node_pool.disk_type
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels          = var.node_pool.node_labels
    resource_labels = local.labels

    # Required for Workload Identity: pods can't read the node's credentials.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
