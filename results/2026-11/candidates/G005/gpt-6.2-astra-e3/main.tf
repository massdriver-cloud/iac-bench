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
  # Account IDs are project-global and limited to 30 characters.
  node_account = "gke-${substr(var.cluster_name, 0, 14)}-${substr(sha256("${var.region}/${var.cluster_name}"), 0, 10)}"
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_account
  display_name = "GKE workers: ${var.cluster_name}"
}

resource "google_project_iam_member" "node_runtime" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project         = var.project_id
  name            = var.cluster_name
  location        = var.region
  network         = "projects/${var.project_id}/global/networks/${local.vpc}"
  subnetwork      = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet}"
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.control_plane_cidr
  }
  datapath_provider = "ADVANCED_DATAPATH"
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  enable_shielded_nodes = true
  master_auth {
    client_certificate_config { issue_client_certificate = false }
  }
  release_channel { channel = "REGULAR" }
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-06T05:00:00Z"
      end_time   = "2024-01-06T13:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }
  logging_config { enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"] }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus { enabled = true }
  }
  deletion_protection      = var.deletion_protection
  remove_default_node_pool = true
  initial_node_count       = 1
  # Even the temporary bootstrap pool must not use the default compute identity.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    metadata        = { disable-legacy-endpoints = "true" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  depends_on = [google_project_iam_member.node_runtime]
}

resource "google_container_node_pool" "workers" {
  project            = var.project_id
  cluster            = google_container_cluster.this.name
  location           = var.region
  name_prefix        = "workers-"
  initial_node_count = var.worker_capacity.min_per_zone
  autoscaling {
    min_node_count  = var.worker_capacity.min_per_zone
    max_node_count  = var.worker_capacity.max_per_zone
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
    machine_type    = var.worker_capacity.machine_type
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
  }
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [initial_node_count]
  }
}
