terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30.0, < 7.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  required_services = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])
  node_roles = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ])
  network_self_link = "projects/${var.project_id}/global/networks/${var.vpc_name}"
  subnet_self_link  = "projects/${var.project_id}/regions/${var.region}/subnetworks/${var.vpc_name}-gke-${var.region}"
}

resource "google_project_service" "required" {
  for_each           = local.required_services
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE node identity for ${var.cluster_name}"
  description  = "Least-privilege node identity. Workloads should use Workload Identity Federation."

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "node_roles" {
  for_each = local.node_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  # These are the network team's existing shared resources; IDs are composed
  # from the agreed naming convention so planning needs no network read access.
  network    = local.network_self_link
  subnetwork = local.subnet_self_link

  # Standard mode is the provider default. The separate managed node pool
  # ensures the provider's small default pool is never left behind.
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection
  enable_shielded_nodes    = true
  enable_legacy_abac       = false
  enable_l4_ilb_subsetting = true

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [true] : []
    content {
      gcp_public_cidrs_access_enabled = false
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
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
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  resource_labels = var.cluster_labels

  depends_on = [
    google_project_service.required,
    google_project_iam_member.node_roles,
  ]
}

resource "google_container_node_pool" "primary" {
  project        = var.project_id
  name           = var.node_pool_name
  location       = var.region
  cluster        = google_container_cluster.this.name
  node_locations = var.node_locations

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
    machine_type    = var.node_machine_type
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"
    disk_size_gb    = var.node_disk_size_gb
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    metadata = {
      "disable-legacy-endpoints" = "true"
    }
    labels = var.node_labels
    tags   = var.node_tags

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  depends_on = [google_project_iam_member.node_roles]
}
