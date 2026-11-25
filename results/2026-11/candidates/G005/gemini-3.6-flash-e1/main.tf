provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  subnet_name = var.subnet_name != null ? var.subnet_name : "${var.vpc_name}-gke-${var.region}"
  sa_name     = var.service_account_name != null ? var.service_account_name : substr("${var.cluster_name}-node-sa", 0, 30)

  node_sa_email = var.create_service_account ? google_service_account.gke_nodes[0].email : var.service_account_email

  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader"
  ]
}

resource "google_service_account" "gke_nodes" {
  count        = var.create_service_account ? 1 : 0
  account_id   = local.sa_name
  display_name = "GKE Node Service Account for ${var.cluster_name}"
  project      = var.project_id
}

resource "google_project_iam_member" "node_sa_roles" {
  for_each = var.create_service_account ? toset(local.node_sa_roles) : []
  project  = var.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.gke_nodes[0].email}"
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  network    = var.vpc_name
  subnetwork = local.subnet_name

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection

  datapath_provider = var.datapath_provider

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  dynamic "master_authorized_networks_config" {
    for_each = var.enable_master_authorized_networks || length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = lookup(cidr_blocks.value, "display_name", null)
        }
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = timeadd(var.maintenance_start_time, "4h")
      recurrence = var.maintenance_recurrence
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

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }
}

resource "google_container_node_pool" "primary" {
  name       = "${var.cluster_name}-primary-pool"
  project    = var.project_id
  cluster    = google_container_cluster.primary.name
  location   = google_container_cluster.primary.location
  node_count = var.enable_autoscaling ? null : var.node_count

  dynamic "autoscaling" {
    for_each = var.enable_autoscaling ? [1] : []
    content {
      min_node_count = var.min_node_count
      max_node_count = var.max_node_count
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    disk_type       = var.disk_type
    spot            = var.spot
    service_account = local.node_sa_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(
      {
        "cluster_name" = var.cluster_name
        "node_pool"    = "primary"
      },
      var.node_labels
    )

    tags = var.node_tags

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}

resource "google_container_node_pool" "additional" {
  for_each   = var.node_pools
  name       = each.key
  project    = var.project_id
  cluster    = google_container_cluster.primary.name
  location   = google_container_cluster.primary.location
  node_count = lookup(each.value, "enable_autoscaling", true) ? null : lookup(each.value, "node_count", 1)

  dynamic "autoscaling" {
    for_each = lookup(each.value, "enable_autoscaling", true) ? [1] : []
    content {
      min_node_count = lookup(each.value, "min_node_count", 1)
      max_node_count = lookup(each.value, "max_node_count", 5)
    }
  }

  management {
    auto_repair  = lookup(each.value, "auto_repair", true)
    auto_upgrade = lookup(each.value, "auto_upgrade", true)
  }

  node_config {
    machine_type    = lookup(each.value, "machine_type", "e2-standard-4")
    disk_size_gb    = lookup(each.value, "disk_size_gb", 100)
    disk_type       = lookup(each.value, "disk_type", "pd-balanced")
    spot            = lookup(each.value, "spot", false)
    service_account = local.node_sa_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(
      {
        "cluster_name" = var.cluster_name
        "node_pool"    = each.key
      },
      lookup(each.value, "labels", {})
    )

    tags = lookup(each.value, "tags", [])

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}
