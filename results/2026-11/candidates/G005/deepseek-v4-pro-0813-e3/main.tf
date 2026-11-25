locals {
  # Least-privilege IAM roles required by a GKE node service account.
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/storage.objectViewer",
    "roles/artifactregistry.reader",
  ]

  # Derive a short, deterministic, collision-resistant node SA account id.
  node_sa_account_id = format(
    "gke-%s-%s-node",
    substr(var.cluster_name, 0, 12),
    substr(md5(var.cluster_name), 0, 8),
  )
}

# Dedicated node service account so nodes do not rely on the project's default
# Compute Engine service account.
resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE nodes for ${var.cluster_name}"
  description  = "Node service account for the ${var.cluster_name} GKE cluster"
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_container_cluster" "this" {
  name        = var.cluster_name
  location    = var.region
  project     = var.project_id
  description = var.cluster_description

  # The network team has already created:
  #   VPC: <vpc_name>
  #   Subnet: <vpc_name>-gke-<region> with secondary ranges "pods" and "services"
  networking_mode = "VPC_NATIVE"
  network         = var.vpc_name
  subnetwork      = "${var.vpc_name}-gke-${var.region}"

  # We manage node pools explicitly; remove the auto-created default pool.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection
  min_master_version  = var.kubernetes_version

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Only expose a public control-plane endpoint when explicitly requested, and
  # always restrict it with authorized networks in that case.
  dynamic "master_authorized_networks_config" {
    for_each = var.enable_private_endpoint ? [] : [1]
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

  # Workload Identity lets product teams bind Kubernetes service accounts to
  # Google Cloud service accounts for Pub/Sub, Cloud Storage, and Cloud SQL.
  dynamic "workload_identity_config" {
    for_each = var.enable_workload_identity ? [1] : []
    content {
      workload_pool = "${var.project_id}.svc.id.goog"
    }
  }

  network_policy {
    enabled  = var.network_policy_enabled
    provider = "CALICO"
  }

  enable_shielded_nodes       = var.enable_shielded_nodes
  enable_intranode_visibility = var.enable_intranode_visibility

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  logging_config {
    enable_components = var.logging_components
  }

  monitoring_config {
    enable_components = var.monitoring_components

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = var.maintenance_recurrence
    }
  }

  cost_management_config {
    enabled = var.enable_cost_allocation
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    dns_cache_config {
      enabled = true
    }
  }
}

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  location = var.region
  cluster  = google_container_cluster.this.name
  project  = var.project_id

  autoscaling {
    min_node_count = each.value.min_node_count
    max_node_count = each.value.max_node_count
  }

  management {
    auto_repair  = each.value.auto_repair
    auto_upgrade = each.value.auto_upgrade
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    image_type      = each.value.image_type
    labels          = each.value.labels
    service_account = each.value.service_account == "" ? google_service_account.gke_nodes.email : each.value.service_account
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = each.value.enable_secure_boot
      enable_integrity_monitoring = true
    }

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }
}