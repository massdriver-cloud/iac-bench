terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  vpc    = "apps-${var.environment}"
  subnet = "${local.vpc}-gke-${var.region}"
  labels = { environment = var.environment, managed_by = "opentofu" }
}

resource "google_service_account" "nodes" {
  account_id   = "gke-node-${substr(sha256("${var.region}/${var.cluster_name}"), 0, 16)}"
  display_name = "GKE nodes: ${var.cluster_name}"
}

resource "google_project_iam_member" "node_runtime" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  name              = var.cluster_name
  location          = var.region
  network           = "projects/${var.project_id}/global/networks/${local.vpc}"
  subnetwork        = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet}"
  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.control_plane_cidr
    master_global_access_config { enabled = true }
  }
  remove_default_node_pool = true
  initial_node_count       = 1
  # Even the short-lived bootstrap pool should not use the default Compute SA.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    metadata        = { disable-legacy-endpoints = "true" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  workload_identity_config { workload_pool = "${var.project_id}.svc.id.goog" }
  master_auth {
    client_certificate_config { issue_client_certificate = false }
  }
  release_channel { channel = "REGULAR" }
  enable_shielded_nodes = true
  enable_legacy_abac    = false
  deletion_protection   = true
  logging_config { enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"] }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus { enabled = true }
  }
  resource_labels = local.labels
  depends_on      = [google_project_iam_member.node_runtime]
}

resource "google_container_node_pool" "workers" {
  name               = "workers"
  location           = var.region
  cluster            = google_container_cluster.this.name
  initial_node_count = var.pool.min_per_zone
  autoscaling {
    min_node_count  = var.pool.min_per_zone
    max_node_count  = var.pool.max_per_zone
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
    machine_type    = var.pool.machine_type
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"
    disk_size_gb    = 100
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    metadata        = { disable-legacy-endpoints = "true" }
    workload_metadata_config { mode = "GKE_METADATA" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    resource_labels = local.labels
  }
  lifecycle { ignore_changes = [initial_node_count] }
}
