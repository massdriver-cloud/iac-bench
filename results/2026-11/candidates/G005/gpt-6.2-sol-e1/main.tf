locals {
  network_name = "apps-${var.environment}"
  subnet_name  = "${local.network_name}-gke-${var.region}"
  network      = "projects/${var.project_id}/global/networks/${local.network_name}"
  subnetwork   = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  node_account_id = "gke-${substr(var.cluster_name, 0, 13)}-${substr(sha256("${var.project_id}/${var.region}/${var.cluster_name}"), 0, 12)}"
  labels          = merge(var.resource_labels, { environment = var.environment })
}

resource "google_project_service" "container" {
  project            = var.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_account_id
  display_name = "GKE nodes: ${var.cluster_name} (${var.region})"
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  network         = local.network
  subnetwork      = local.subnetwork
  node_locations  = var.node_locations
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection
  resource_labels          = local.labels

  # Even the temporary bootstrap pool must not use the Compute Engine default identity.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  private_cluster_config {
    enable_private_nodes = true
  }

  # Use the IAM-gated DNS endpoint; don't expose either control-plane IP endpoint.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
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

  enable_legacy_abac    = false
  enable_shielded_nodes = true
  datapath_provider     = "ADVANCED_DATAPATH"

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
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

  depends_on = [google_project_service.container, google_project_iam_member.nodes]

  lifecycle {
    precondition {
      condition = var.node_locations == null ? true : alltrue([
        for zone in var.node_locations : startswith(zone, "${var.region}-")
      ])
      error_message = "All node_locations must belong to the cluster region."
    }
  }
}

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  project  = var.project_id
  name     = each.key
  location = var.region
  cluster  = google_container_cluster.this.name

  initial_node_count = each.value.min_nodes_per_zone

  autoscaling {
    min_node_count  = each.value.min_nodes_per_zone
    max_node_count  = each.value.max_nodes_per_zone
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
    machine_type    = each.value.machine_type
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"
    disk_size_gb    = each.value.disk_size_gb
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    resource_labels = local.labels

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
    # Use the minimum only when creating a pool. Changing autoscaling bounds must not replace it.
    ignore_changes = [initial_node_count]
  }
}
