locals {
  subnet_name    = "${var.vpc_name}-gke-${var.region}"
  workload_pool  = "${var.project_id}.svc.id.goog"
  node_sa_id     = "${substr(var.cluster_name, 0, 18)}-${substr(sha256(var.cluster_name), 0, 8)}"
  node_pool_name = "${substr(var.cluster_name, 0, 25)}-workers"
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_id
  display_name = "GKE node service account for ${var.cluster_name}"
  description  = "Node identity for GKE cluster ${var.cluster_name}; application identities should use Workload Identity."
}

# The recommended GKE node role provides only the permissions required by
# Google-managed node agents. Workloads obtain their own service identities via WI.
resource "google_project_iam_member" "node_service_account" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  deletion_protection      = true
  remove_default_node_pool = true
  initial_node_count       = 1
  network                  = "projects/${var.project_id}/global/networks/${var.vpc_name}"
  subnetwork               = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"
  networking_mode          = "VPC_NATIVE"
  datapath_provider        = "ADVANCED_DATAPATH"
  enable_shielded_nodes    = true
  enable_legacy_abac       = false
  allow_net_admin          = false
  resource_labels          = { managed_by = "opentofu", cluster = var.cluster_name }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = local.workload_pool
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.authorized_master_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "SYSTEM_METRICS"]
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  depends_on = [google_project_iam_member.node_service_account]
}

resource "google_container_node_pool" "primary" {
  project            = var.project_id
  name               = local.node_pool_name
  location           = var.region
  cluster            = google_container_cluster.this.name
  initial_node_count = var.min_nodes_per_zone

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
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.machine_type
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
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      managed_by = "opentofu"
      pool       = "primary"
    }
  }

  lifecycle {
    precondition {
      condition     = var.max_nodes_per_zone >= var.min_nodes_per_zone
      error_message = "max_nodes_per_zone must be at least min_nodes_per_zone."
    }
  }
}
