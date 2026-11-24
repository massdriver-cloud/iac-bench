locals {
  subnetwork = var.subnetwork != null ? var.subnetwork : "${var.network}-gke-${var.region}"

  # Default service account email if none provided
  node_service_account_email = var.node_service_account != null ? var.node_service_account : (length(google_service_account.node_sa) > 0 ? google_service_account.node_sa[0].email : "")

  # Node SA IAM roles following Google Cloud least privilege recommendation
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ]
}

# Dedicated least-privilege service account for GKE nodes
resource "google_service_account" "node_sa" {
  count        = var.node_service_account == null ? 1 : 0
  project      = var.project_id
  account_id   = var.node_service_account_id != null ? var.node_service_account_id : "${substr(lower(replace("${var.cluster_name}-node", "_", "-")), 0, 22)}-sa"
  display_name = "GKE Node SA for ${var.cluster_name}"
}

resource "google_project_iam_member" "node_sa_roles" {
  for_each = var.node_service_account == null ? toset(local.node_sa_roles) : []
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.node_sa[0].email}"
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  network    = var.network
  subnetwork = local.subnetwork

  # GKE Standard: remove default pool and manage node pools separately
  remove_default_node_pool = true
  initial_node_count       = 1

  # VPC-Native configuration
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Dataplane V2 (Cilium-powered network policy and routing)
  datapath_provider = "ADVANCED_DATAPATH"

  # Workload Identity Federation
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Security: Shielded nodes
  enable_shielded_nodes = true

  # Security: Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Master Authorized Networks
  dynamic "master_authorized_networks_config" {
    for_each = var.enable_master_authorized_networks || length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      gcp_public_cidrs_access_enabled = var.master_authorized_networks_gcp_public_cidrs_access_enabled
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = lookup(cidr_blocks.value, "display_name", null)
        }
      }
    }
  }

  # Production Addons
  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    gcs_fuse_csi_driver_config {
      enabled = true
    }
  }

  # Observability
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Release Channel
  release_channel {
    channel = var.release_channel
  }

  # Production Maintenance Policy
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = var.maintenance_recurrence
    }
  }

  deletion_protection = var.deletion_protection
}

# Separately managed node pools
resource "google_container_node_pool" "pools" {
  for_each       = var.node_pools
  name           = each.key
  cluster        = google_container_cluster.primary.name
  location       = var.region
  project        = var.project_id
  node_locations = each.value.node_locations

  initial_node_count = each.value.initial_node_count

  autoscaling {
    min_node_count  = each.value.min_count
    max_node_count  = each.value.max_count
    location_policy = each.value.location_policy
  }

  management {
    auto_repair  = each.value.auto_repair
    auto_upgrade = each.value.auto_upgrade
  }

  upgrade_settings {
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = each.value.image_type

    service_account = local.node_service_account_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = each.value.enable_secure_boot
      enable_integrity_monitoring = each.value.enable_integrity_monitoring
    }

    labels = merge(
      {
        "cluster"   = var.cluster_name
        "node-pool" = each.key
      },
      each.value.labels
    )

    tags = concat(
      [var.cluster_name, "${var.cluster_name}-node"],
      each.value.tags
    )

    metadata = merge(
      {
        "disable-legacy-endpoints" = "true"
      },
      each.value.metadata
    )

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}
