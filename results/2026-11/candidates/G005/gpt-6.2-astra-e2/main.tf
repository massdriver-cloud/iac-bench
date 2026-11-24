locals {
  vpc = "apps-${var.environment}"
  # Stable, project-unique ID even for clusters with long names or the same name in different regions.
  node_identity = "gke-${substr(var.cluster_name, 0, 12)}-${substr(sha256("${var.region}/${var.cluster_name}"), 0, 10)}"
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_identity
  display_name = "GKE nodes: ${var.cluster_name} (${var.region})"
}

resource "google_project_iam_member" "node_runtime" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  network         = "projects/${var.project_id}/global/networks/${local.vpc}"
  subnetwork      = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.vpc}-gke-${var.region}"
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

  datapath_provider     = "ADVANCED_DATAPATH"
  enable_shielded_nodes = true
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
  logging_service     = "logging.googleapis.com/kubernetes"
  monitoring_service  = "monitoring.googleapis.com/kubernetes"
  deletion_protection = var.deletion_protection
  resource_labels     = { environment = var.environment, managed_by = "opentofu" }

  # GKE requires a temporary pool during cluster creation. It uses the same restricted identity.
  remove_default_node_pool = true
  initial_node_count       = 1
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  depends_on = [google_project_iam_member.node_runtime]
}

resource "google_container_node_pool" "workers" {
  project            = var.project_id
  location           = var.region
  cluster            = google_container_cluster.this.name
  name               = "workers"
  initial_node_count = 1
  autoscaling {
    min_node_count  = 1
    max_node_count  = var.max_nodes_per_zone
    location_policy = "BALANCED"
  }
  management {
    auto_upgrade = true
    auto_repair  = true
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
    metadata        = { disable-legacy-endpoints = "true" }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}
