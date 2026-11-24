locals {
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"
  network     = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork  = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"
}

resource "google_service_account" "nodes" {
  account_id   = "gke-${substr(var.cluster_name, 0, 12)}-${substr(sha256("${var.region}/${var.cluster_name}"), 0, 12)}"
  display_name = "GKE nodes: ${var.cluster_name} (${var.region})"
}

resource "google_project_iam_member" "node_service" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.nodes.member
}

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region

  # Standard is the provider default; the Autopilot toggle conflicts with
  # Standard-only settings even when explicitly set to false.
  deletion_protection = var.deletion_protection

  network           = local.network
  subnetwork        = local.subnetwork
  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes = true
  }

  # IAM-authenticated DNS endpoint only; no public or private IP endpoint for clients.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic    = true
      enable_k8s_certs_via_dns  = false
      enable_k8s_tokens_via_dns = false
    }
    ip_endpoints_config {
      enabled = false
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

  enable_shielded_nodes = true
  node_locations        = var.node_zones

  # GKE requires a bootstrap pool at creation. The provider removes it before
  # creating the separately managed application pool.
  remove_default_node_pool = true
  initial_node_count       = 1
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    recurring_window {
      start_time = "2025-01-04T06:00:00Z"
      end_time   = "2025-01-04T12:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
    managed_prometheus {
      enabled = true
    }
  }

  dynamic "database_encryption" {
    for_each = var.secrets_kms_key == null ? [] : [var.secrets_kms_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  resource_labels = merge(var.resource_labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  lifecycle {
    precondition {
      condition = var.node_zones == null ? true : alltrue([
        for zone in var.node_zones : can(regex("^${var.region}-[a-z]$", zone))
      ])
      error_message = "Each node zone must be in the selected region."
    }
    precondition {
      condition = var.secrets_kms_key == null ? true : can(regex(
        "^projects/[^/]+/locations/${var.region}/keyRings/[^/]+/cryptoKeys/[^/]+$", var.secrets_kms_key
      ))
      error_message = "secrets_kms_key must be a full CryptoKey resource ID in the cluster region."
    }
  }

  depends_on = [google_project_iam_member.node_service]
}

resource "google_container_node_pool" "general" {
  name     = "general"
  cluster  = google_container_cluster.this.id
  location = var.region

  node_locations     = var.node_zones
  initial_node_count = var.node_pool.min_nodes_per_zone

  autoscaling {
    min_node_count  = var.node_pool.min_nodes_per_zone
    max_node_count  = var.node_pool.max_nodes_per_zone
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
    machine_type    = var.node_pool.machine_type
    disk_type       = "pd-balanced"
    disk_size_gb    = var.node_pool.disk_size_gb
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
  }

  lifecycle {
    # This is a creation-time seed, not a request to recreate the pool when
    # the autoscaler minimum changes.
    ignore_changes = [initial_node_count]
  }
}
