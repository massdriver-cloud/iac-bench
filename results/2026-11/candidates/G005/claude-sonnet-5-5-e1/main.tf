locals {
  vpc_name   = "apps-${var.environment}"
  subnetwork = "${local.vpc_name}-gke-${var.region}"
  network_id = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnet_id  = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnetwork}"

  labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]
}

# Least-privilege identity for nodes. Workloads get their own identities via
# Workload Identity Federation for GKE and do not use this account.
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes for ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.name
  location = var.region # regional: control plane and nodes span zones

  network    = local.network_id
  subnetwork = local.subnet_id

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

  # Dataplane V2 (Cilium): enforces Kubernetes NetworkPolicy, so teams sharing
  # the cluster can isolate their namespaces.
  datapath_provider = "ADVANCED_DATAPATH"

  release_channel {
    channel = var.release_channel
  }

  # Workload Identity: lets pods call Pub/Sub, GCS, Cloud SQL, etc. with
  # per-workload Google identities instead of node credentials or keys.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private nodes (no public IPs); the API endpoint is restricted to the
  # authorized networks below.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        display_name = cidr_blocks.key
        cidr_block   = cidr_blocks.value
      }
    }
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_key == null ? [] : [1]
    content {
      state    = "ENCRYPTED"
      key_name = var.database_encryption_key
    }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # Disable legacy auth methods.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  enable_shielded_nodes = true

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER"]
    managed_prometheus {
      enabled = true
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
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
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "primary" {
  project  = var.project_id
  name     = "primary"
  cluster  = google_container_cluster.this.name
  location = var.region

  # Per-zone counts; the autoscaler balances across zones.
  initial_node_count = var.node_min_count

  autoscaling {
    min_node_count  = var.node_min_count
    max_node_count  = var.node_max_count
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
    machine_type    = var.node_machine_type
    disk_size_gb    = var.node_disk_size_gb
    disk_type       = "pd-balanced"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = local.labels

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Pods see the GKE metadata server (Workload Identity), not the node's SA.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

resource "google_compute_router" "nat" {
  count = var.create_cloud_nat ? 1 : 0

  project = var.project_id
  name    = "${var.name}-nat"
  region  = var.region
  network = local.network_id
}

resource "google_compute_router_nat" "nat" {
  count = var.create_cloud_nat ? 1 : 0

  project                            = var.project_id
  name                               = "${var.name}-nat"
  router                             = google_compute_router.nat[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = local.subnet_id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
