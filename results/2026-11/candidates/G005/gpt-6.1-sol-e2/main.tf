locals {
  network_name = "apps-${var.environment}"
  zones        = var.node_locations != null ? var.node_locations : slice(data.google_compute_zones.available.names, 0, 3)
  cluster_id   = substr(sha256("${var.project_id}/${var.region}/${var.cluster_name}"), 0, 16)
}

resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "artifactregistry.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_compute_zones" "available" {
  project    = var.project_id
  region     = var.region
  status     = "UP"
  depends_on = [google_project_service.required]
}

data "google_compute_subnetwork" "gke" {
  project    = var.project_id
  region     = var.region
  name       = "${local.network_name}-gke-${var.region}"
  depends_on = [google_project_service.required]
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "gke-node-${local.cluster_id}"
  display_name = "GKE ${var.cluster_name} nodes"
  depends_on   = [google_project_service.required]
}

resource "google_project_iam_member" "node_telemetry" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "image_reader" {
  for_each = var.artifact_registry_projects
  project  = each.value
  role     = "roles/artifactregistry.reader"
  member   = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project                  = var.project_id
  name                     = var.cluster_name
  location                 = var.region
  node_locations           = local.zones
  description              = "Managed regional GKE Standard cluster for ${var.environment}"
  network                  = "projects/${var.project_id}/global/networks/${local.network_name}"
  subnetwork               = data.google_compute_subnetwork.gke.self_link
  networking_mode          = "VPC_NATIVE"
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection
  enable_shielded_nodes    = true
  enable_legacy_abac       = false
  datapath_provider        = "ADVANCED_DATAPATH"

  resource_labels = {
    environment = var.environment
    managed_by  = "opentofu"
  }

  release_channel {
    channel = "REGULAR"
  }

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

  # No Internet-accessible Kubernetes API endpoint. Private network routing and
  # IAM/RBAC are required for operators.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
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
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = true
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

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
  }

  # Even the short-lived default pool uses the restricted identity and shielded
  # configuration. All durable capacity is managed as separate node pools.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    machine_type    = "e2-standard-4"
    disk_type       = "pd-balanced"
    disk_size_gb    = 100
    image_type      = "COS_CONTAINERD"
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
    precondition {
      condition     = alltrue([for range_name in ["pods", "services"] : contains([for range in data.google_compute_subnetwork.gke.secondary_ip_range : range.range_name], range_name)])
      error_message = "The existing subnet must contain secondary ranges named pods and services."
    }
    precondition {
      condition     = endswith(data.google_compute_subnetwork.gke.network, "/networks/${local.network_name}")
      error_message = "The subnet must belong to the selected environment VPC."
    }
    precondition {
      condition     = data.google_compute_subnetwork.gke.private_ip_google_access
      error_message = "The network team must enable Private Google Access on the existing subnet for private nodes to reach Google APIs."
    }
    precondition {
      condition     = length(local.zones) == 3 && alltrue([for zone in local.zones : startswith(zone, "${var.region}-")])
      error_message = "Three node zones in the selected region are required."
    }
  }

  depends_on = [google_project_iam_member.node_telemetry]
}

resource "google_container_node_pool" "this" {
  for_each = var.node_pools
  project  = var.project_id
  name     = each.key
  location = var.region
  cluster  = google_container_cluster.this.name

  node_locations = local.zones

  autoscaling {
    total_min_node_count = each.value.min_nodes
    total_max_node_count = each.value.max_nodes
    location_policy      = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = "pd-balanced"
    image_type      = "COS_CONTAINERD"
    spot            = false
    preemptible     = false
    labels          = merge(each.value.labels, { environment = var.environment })
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
    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  depends_on = [google_project_iam_member.image_reader]
}

resource "google_service_account" "workload" {
  for_each     = var.workload_identities
  project      = var.project_id
  account_id   = "gke-wi-${substr(sha256("${local.cluster_id}/${each.key}"), 0, 20)}"
  display_name = "${var.cluster_name} workload ${each.key}"
  depends_on   = [google_project_service.required]
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each           = var.workload_identities
  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.kubernetes_service_account}]"
  depends_on         = [google_container_cluster.this]
}
