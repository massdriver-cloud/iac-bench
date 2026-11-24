locals {
  network_name = "apps-${var.environment}"
  network      = "projects/${var.project_id}/global/networks/${local.network_name}"
  subnetwork   = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.network_name}-gke-${var.region}"
  labels = merge(var.resource_labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })
  workload_roles = merge({}, [for account, identity in var.workload_identities : {
    for role in identity.project_roles : "${account}/${role}" => {
      account = account
      role    = role
    }
  }]...)
}

# APIs are shared project resources: leave them enabled on destroy.
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

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE ${var.cluster_name} nodes (not workloads)"
  depends_on   = [google_project_service.required]
}

# No default Compute Engine account, Editor role, service-account keys,
# or application permissions on nodes. Additive members do not replace IAM policies.
resource "google_project_iam_member" "node_telemetry" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_artifact_registry_repository_iam_member" "image_pull" {
  for_each   = var.artifact_registry_repositories
  project    = each.value.project_id
  location   = each.value.location
  repository = each.value.repository
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.nodes.email}"
  depends_on = [google_project_service.required]
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  # Omitting enable_autopilot selects Standard. The temporary default
  # pool is removed; all lasting pools are independently managed below.
  remove_default_node_pool = true
  initial_node_count       = 1
  node_locations           = var.node_locations
  deletion_protection      = var.deletion_protection
  resource_labels          = local.labels
  networking_mode          = "VPC_NATIVE"
  network                  = local.network
  subnetwork               = local.subnetwork
  datapath_provider        = "ADVANCED_DATAPATH"
  enable_shielded_nodes    = true
  enable_legacy_abac       = false

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
    stack_type                    = "IPV4"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = !var.enable_public_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled      = false
    private_endpoint_enforcement_enabled = true
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        display_name = cidr_blocks.value.display_name
        cidr_block   = cidr_blocks.value.cidr_block
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

  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
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

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "API_SERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
    managed_prometheus {
      enabled = true
    }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # Secure even the short-lived bootstrap pool.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    image_type      = "COS_CONTAINERD"
    metadata        = { disable-legacy-endpoints = "true" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    precondition {
      condition     = !var.enable_public_endpoint || length(var.authorized_networks) > 0
      error_message = "A public endpoint requires explicit trusted authorized_networks."
    }
    precondition {
      condition     = var.node_locations == null ? true : alltrue([for zone in var.node_locations : startswith(zone, "${var.region}-")])
      error_message = "All node_locations must belong to region."
    }
    precondition {
      condition     = var.node_locations == null ? true : alltrue([for pool in values(var.node_pools) : pool.min_nodes >= length(var.node_locations)])
      error_message = "Each pool's total minimum must accommodate at least one node per selected zone."
    }
    precondition {
      condition     = !contains(keys(var.workload_identities), "${var.cluster_name}-nodes")
      error_message = "A workload service account cannot have the same account ID as the node service account."
    }
  }

  depends_on = [google_project_service.required, google_project_iam_member.node_telemetry]

  timeouts {
    create = "45m"
    update = "60m"
    delete = "45m"
  }
}

resource "google_container_node_pool" "this" {
  for_each = var.node_pools
  project  = var.project_id
  name     = each.key
  cluster  = google_container_cluster.this.name
  location = var.region

  node_locations     = var.node_locations
  initial_node_count = 1
  max_pods_per_node  = each.value.max_pods_per_node

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
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    # OAuth scope is only a ceiling; the dedicated account's IAM controls access.
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    spot            = false
    preemptible     = false
    labels          = merge(each.value.labels, { environment = var.environment })
    resource_labels = local.labels
    metadata        = { disable-legacy-endpoints = "true" }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
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

  depends_on = [google_project_iam_member.node_telemetry, google_artifact_registry_repository_iam_member.image_pull]

  timeouts {
    create = "45m"
    update = "60m"
    delete = "45m"
  }
}

resource "google_service_account" "workload" {
  for_each     = var.workload_identities
  project      = var.project_id
  account_id   = each.key
  display_name = "GKE ${each.value.namespace}/${each.value.kubernetes_service_account}"
  depends_on   = [google_project_service.required]
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each           = var.workload_identities
  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.kubernetes_service_account}]"
  depends_on         = [google_container_cluster.this]
}

resource "google_project_iam_member" "workload_role" {
  for_each = local.workload_roles
  project  = var.project_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.workload[each.value.account].email}"
}
