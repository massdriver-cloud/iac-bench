locals {
  network_name = "apps-${var.environment}"
  subnet_name  = "apps-${var.environment}-gke-${var.region}"
  node_roles = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ])
}

resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "gke-${var.cluster_name}"
  display_name = "GKE ${var.cluster_name} nodes"
  depends_on   = [google_project_service.required]
}

resource "google_project_iam_member" "node_roles" {
  for_each = local.node_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "main" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  network           = "projects/${var.project_id}/global/networks/${local.network_name}"
  subnetwork        = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"
  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH"
  node_locations    = sort(tolist(var.zones))

  # GKE requires an initial default pool; remove it immediately and manage a separate pool.
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection
  enable_shielded_nodes    = true
  # Use the dedicated identity even for the short-lived bootstrap pool.
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
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    master_global_access_config {
      enabled = false
    }
  }
  master_authorized_networks_config {
    private_endpoint_enforcement_enabled = true
    dynamic "cidr_blocks" {
      for_each = var.admin_cidrs
      content {
        cidr_block = cidr_blocks.value
      }
    }
  }
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  release_channel {
    channel = "REGULAR"
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
  vertical_pod_autoscaling {
    enabled = true
  }
  depends_on = [google_project_service.required, google_project_iam_member.node_roles]
}

resource "google_container_node_pool" "general" {
  project            = var.project_id
  name               = "general"
  location           = var.region
  cluster            = google_container_cluster.main.name
  node_locations     = sort(tolist(var.zones))
  initial_node_count = var.min_nodes_per_zone

  autoscaling {
    min_node_count = var.min_nodes_per_zone
    max_node_count = var.max_nodes_per_zone
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
    machine_type    = var.node_machine_type
    disk_type       = "pd-balanced"
    disk_size_gb    = 100
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
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }
  }
  depends_on = [google_project_iam_member.node_roles]
}
