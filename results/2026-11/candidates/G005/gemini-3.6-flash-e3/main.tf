locals {
  network_name = coalesce(var.network_name, "apps-${var.environment}")
  subnet_name  = coalesce(var.subnet_name, "${local.network_name}-gke-${var.region}")
}

resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "Service Account for GKE Cluster ${var.cluster_name} Nodes"
}

resource "google_project_iam_member" "node_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader"
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = local.network_name
  subnetwork = local.subnet_name

  ip_allocation_policy {
    cluster_secondary_range_name  = var.ip_range_pods
    services_secondary_range_name = var.ip_range_services
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  release_channel {
    channel = var.release_channel
  }

  datapath_provider = "ADVANCED_DATAPATH"

  addons_config {
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = var.maintenance_recurrence
    }
  }

  deletion_protection = var.deletion_protection

  resource_labels = merge(
    {
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.cluster_resource_labels
  )
}

resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  name               = each.key
  location           = var.region
  cluster            = google_container_cluster.primary.name
  project            = var.project_id
  initial_node_count = lookup(each.value, "initial_count", 1)

  autoscaling {
    min_node_count = lookup(each.value, "min_count", 1)
    max_node_count = lookup(each.value, "max_count", 5)
  }

  management {
    auto_repair  = lookup(each.value, "auto_repair", true)
    auto_upgrade = lookup(each.value, "auto_upgrade", true)
  }

  node_config {
    machine_type = lookup(each.value, "machine_type", "e2-standard-4")
    disk_size_gb = lookup(each.value, "disk_size_gb", 100)
    disk_type    = lookup(each.value, "disk_type", "pd-balanced")
    spot         = lookup(each.value, "spot", false)

    service_account = google_service_account.gke_nodes.email
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
        environment = var.environment
      },
      lookup(each.value, "labels", {})
    )

    tags = lookup(each.value, "tags", [])

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  node_locations = lookup(each.value, "node_locations", null)
}
