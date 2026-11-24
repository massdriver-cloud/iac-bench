locals {
  network_name = "apps-${var.environment}"
  subnet_name  = "${local.network_name}-gke-${var.region}"
  labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "opentofu"
  })
  node_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
}

# These services are shared project prerequisites; never disable them on destroy.
resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "artifactregistry.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Network objects are owned exclusively by the network team.
data "google_compute_network" "existing" {
  project    = var.project_id
  name       = local.network_name
  depends_on = [google_project_service.required]
}

data "google_compute_subnetwork" "existing" {
  project    = var.project_id
  region     = var.region
  name       = local.subnet_name
  depends_on = [google_project_service.required]
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE ${var.cluster_name} nodes (not workloads)"
  depends_on   = [google_project_service.required]
}

# Additive IAM: do not replace project IAM policies or grant Editor to nodes.
resource "google_project_iam_member" "nodes" {
  for_each = local.node_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project             = var.project_id
  name                = var.cluster_name
  location            = var.region
  description         = "Shared production-grade Standard cluster managed by OpenTofu"
  deletion_protection = var.deletion_protection
  # Omitting enable_autopilot selects Standard and avoids provider conflicts.

  network    = data.google_compute_network.existing.self_link
  subnetwork = data.google_compute_subnetwork.existing.self_link

  # The transient default pool is immediately removed; only the separately
  # managed pool below is retained. Secure its nodes during creation as well.
  remove_default_node_pool = true
  initial_node_count       = 1
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    image_type      = "COS_CONTAINERD"
    metadata        = { disable-legacy-endpoints = "true" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.control_plane_cidr
    master_global_access_config {
      enabled = true
    }
  }
  # No public control-plane endpoint. Private connectivity and Kubernetes/IAM
  # authorization are required; the network team controls routed client access.
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false
  }

  datapath_provider         = "ADVANCED_DATAPATH"
  enable_shielded_nodes     = true
  enable_legacy_abac        = false
  default_max_pods_per_node = 64
  resource_labels           = local.labels
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  release_channel {
    channel = "REGULAR"
  }
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = "FREQ=DAILY"
    }
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
  }
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
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
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }
  vertical_pod_autoscaling {
    enabled = true
  }

  lifecycle {
    precondition {
      condition     = data.google_compute_subnetwork.existing.network == data.google_compute_network.existing.self_link
      error_message = "The GKE subnet must belong to the selected environment VPC."
    }
    precondition {
      condition = alltrue([
        for name in ["pods", "services"] : contains([
          for range in data.google_compute_subnetwork.existing.secondary_ip_range : range.range_name
        ], name)
      ])
      error_message = "The existing subnet must contain secondary ranges named pods and services."
    }
  }
  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "primary" {
  project            = var.project_id
  name               = "general"
  cluster            = google_container_cluster.this.name
  location           = var.region
  initial_node_count = 1
  max_pods_per_node  = 64

  autoscaling {
    total_min_node_count = var.min_nodes
    total_max_node_count = var.max_nodes
    location_policy      = "BALANCED"
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
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"
    disk_size_gb    = 100
    spot            = false
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = local.labels
    metadata        = { disable-legacy-endpoints = "true" }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  depends_on = [google_project_iam_member.nodes]
}
