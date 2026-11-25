locals {
  network = "apps-${var.environment}"
  labels  = { environment = var.environment, managed-by = "opentofu", cluster = var.name }
  workload_roles = merge({}, [for key, identity in var.workload_identities : {
    for role in identity.project_roles : "${key}/${role}" => { identity = key, role = role }
  }]...)
}

resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com", "container.googleapis.com", "iam.googleapis.com",
    "iamcredentials.googleapis.com", "logging.googleapis.com", "monitoring.googleapis.com",
    "artifactregistry.googleapis.com", "cloudresourcemanager.googleapis.com", "sts.googleapis.com"
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE ${var.name} nodes (not workloads)"
  depends_on   = [google_project_service.required]
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_artifact_registry_repository_iam_member" "pull" {
  for_each   = var.artifact_registry_repositories
  project    = each.value.project
  location   = each.value.location
  repository = each.value.repository
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.nodes.email}"
  depends_on = [google_project_service.required]
}

resource "google_container_cluster" "this" {
  project                  = var.project_id
  name                     = var.name
  location                 = var.region
  node_locations           = var.node_locations
  deletion_protection      = var.deletion_protection
  network                  = "projects/${var.project_id}/global/networks/${local.network}"
  subnetwork               = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.network}-gke-${var.region}"
  networking_mode          = "VPC_NATIVE"
  datapath_provider        = "ADVANCED_DATAPATH"
  remove_default_node_pool = true
  initial_node_count       = 1
  resource_labels          = local.labels
  enable_shielded_nodes    = true
  enable_legacy_abac       = false

  # Standard is the provider default. Even enable_autopilot=false conflicts
  # with Standard-only fields in the provider schema.
  # Harden even the temporary default pool, removed immediately after creation.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    image_type      = "COS_CONTAINERD"
    metadata        = { disable-legacy-endpoints = "true" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    workload_metadata_config { mode = "GKE_METADATA" }
  }
  release_channel { channel = "REGULAR" }
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.control_plane_ipv4_cidr
    master_global_access_config { enabled = true }
  }
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled      = false
    private_endpoint_enforcement_enabled = true
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        display_name = cidr_blocks.key
        cidr_block   = cidr_blocks.value
      }
    }
  }
  workload_identity_config { workload_pool = "${var.project_id}.svc.id.goog" }
  master_auth {
    client_certificate_config { issue_client_certificate = false }
  }
  dynamic "authenticator_groups_config" {
    for_each = var.security_group == null ? [] : [var.security_group]
    content { security_group = authenticator_groups_config.value }
  }
  addons_config {
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    gcp_filestore_csi_driver_config { enabled = false }
    gce_persistent_disk_csi_driver_config { enabled = true }
  }
  logging_config { enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"] }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus { enabled = true }
  }
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = timeadd(var.maintenance_start_time, "4h")
      recurrence = "FREQ=DAILY"
    }
  }
  lifecycle {
    precondition {
      condition     = var.node_locations == null ? true : alltrue([for zone in var.node_locations : startswith(zone, "${var.region}-")])
      error_message = "All node zones must belong to the selected region."
    }
  }
  depends_on = [google_project_service.required, google_project_iam_member.nodes]
}

resource "google_container_node_pool" "this" {
  for_each           = var.node_pools
  project            = var.project_id
  name               = each.key
  location           = var.region
  cluster            = google_container_cluster.this.name
  initial_node_count = each.value.min_node_count
  max_pods_per_node  = each.value.max_pods
  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
    location_policy = "BALANCED"
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
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = "pd-balanced"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = merge(each.value.labels, local.labels)
    metadata        = { disable-legacy-endpoints = "true" }
    spot            = false
    preemptible     = false
    workload_metadata_config { mode = "GKE_METADATA" }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  depends_on = [google_artifact_registry_repository_iam_member.pull]
}

resource "google_service_account" "workload" {
  for_each = var.workload_identities
  project  = var.project_id
  # Final letter ensures minimum length six even with shortest input names;
  # maximum length is 30 (20 + 1 + 8 + 1).
  account_id   = "${var.name}-${each.key}w"
  display_name = substr("GKE ${var.name}: ${each.value.namespace}/${each.value.service_account}", 0, 100)
  depends_on   = [google_project_service.required]
}

resource "google_service_account_iam_member" "workload" {
  for_each           = var.workload_identities
  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.service_account}]"
  depends_on         = [google_container_cluster.this]
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_roles
  project  = var.project_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.workload[each.value.identity].email}"
}
