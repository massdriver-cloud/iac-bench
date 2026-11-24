locals {
  network_name = "apps-${var.environment}"
  network      = "projects/${var.project_id}/global/networks/${local.network_name}"
  subnetwork   = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.network_name}-gke-${var.region}"
  node_roles = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ])
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "gke-${substr(var.cluster_name, 0, 19)}-${substr(sha256("${var.region}/${var.cluster_name}"), 0, 6)}"
  display_name = "GKE nodes for ${var.cluster_name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = local.node_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  network    = local.network
  subnetwork = local.subnetwork

  # A temporary default pool is required by the API, then removed. Workloads run
  # on the independently managed, autoscaled pool below.
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection

  # Do not use the project's default compute service account, even temporarily.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
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

  networking_mode           = "VPC_NATIVE"
  default_max_pods_per_node = 64
  enable_shielded_nodes     = true
  enable_legacy_abac        = false

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    master_global_access_config {
      enabled = false
    }
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }
  addons_config {
    network_policy_config {
      disabled = false
    }
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

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "general" {
  project  = var.project_id
  name     = "general"
  location = var.region
  cluster  = google_container_cluster.this.name

  # Regional node counts are per zone. GKE chooses three zones by default.
  initial_node_count = var.min_nodes_per_zone
  max_pods_per_node  = 64
  autoscaling {
    min_node_count  = var.min_nodes_per_zone
    max_node_count  = var.max_nodes_per_zone
    location_policy = "BALANCED"
  }
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
  node_config {
    machine_type    = var.machine_type
    disk_type       = "pd-balanced"
    disk_size_gb    = var.node_disk_size_gb
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
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
    precondition {
      condition     = var.max_nodes_per_zone >= var.min_nodes_per_zone
      error_message = "max_nodes_per_zone must be at least min_nodes_per_zone."
    }
  }
  depends_on = [google_project_iam_member.nodes]
}
