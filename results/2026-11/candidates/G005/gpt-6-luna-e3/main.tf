locals {
  subnet_name     = "${var.network_name}-gke-${var.region}"
  node_account_id = "${substr(var.cluster_name, 0, 17)}-${substr(sha1(var.cluster_name), 0, 6)}-nodes"
  labels = {
    environment = lower(replace(var.environment, "_", "-"))
    managed_by  = "opentofu"
  }
}

resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_compute_network" "cluster" {
  name       = var.network_name
  project    = var.project_id
  depends_on = [google_project_service.required]
}

data "google_compute_subnetwork" "cluster" {
  name       = local.subnet_name
  region     = var.region
  project    = var.project_id
  depends_on = [google_project_service.required]
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_account_id
  display_name = "GKE node identity for ${var.cluster_name}"
  description  = "Least-privilege Google identity for GKE node-level operations; workload identities should be used for application access."
  depends_on   = [google_project_service.required]
}

resource "google_project_iam_member" "node_roles" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  network    = data.google_compute_network.cluster.id
  subnetwork = data.google_compute_subnetwork.cluster.id

  deletion_protection         = var.deletion_protection
  remove_default_node_pool    = true
  initial_node_count          = 1
  default_max_pods_per_node   = 110
  enable_intranode_visibility = true
  enable_l4_ilb_subsetting    = true
  enable_shielded_nodes       = true
  networking_mode             = "VPC_NATIVE"
  logging_service             = "logging.googleapis.com/kubernetes"
  monitoring_service          = "monitoring.googleapis.com/kubernetes"
  resource_labels             = local.labels

  release_channel {
    channel = var.release_channel
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

  dynamic "master_authorized_networks_config" {
    for_each = length(var.authorized_master_networks) > 0 ? [true] : []
    content {
      gcp_public_cidrs_access_enabled = false
      dynamic "cidr_blocks" {
        for_each = var.authorized_master_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
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

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "05:00"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }

  depends_on = [
    google_project_service.required,
    google_project_iam_member.node_roles,
  ]
}

resource "google_container_node_pool" "workload" {
  name     = "workload"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  initial_node_count = var.node_min_count

  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
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
    disk_type       = "pd-balanced"
    disk_size_gb    = var.node_disk_size_gb
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = local.labels

    metadata = {
      "disable-legacy-endpoints" = "true"
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
    ignore_changes = [initial_node_count]
    precondition {
      condition     = var.node_min_count <= var.node_max_count
      error_message = "node_min_count must be less than or equal to node_max_count."
    }
  }
}
