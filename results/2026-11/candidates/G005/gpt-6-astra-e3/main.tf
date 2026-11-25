locals {
  network_name = "apps-${var.environment}"
  labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })
  workload_role_bindings = merge({}, [for account, workload in var.workload_identities : {
    for role in workload.project_roles : "${account}/${role}" => { account = account, role = role }
  }]...)
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
    "binaryauthorization.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_compute_network" "existing" {
  project    = var.project_id
  name       = local.network_name
  depends_on = [google_project_service.required]
}

data "google_compute_subnetwork" "existing" {
  project    = var.project_id
  region     = var.region
  name       = "${local.network_name}-gke-${var.region}"
  depends_on = [google_project_service.required]
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node"
  display_name = "GKE ${var.cluster_name} nodes (not workloads)"
  depends_on   = [google_project_service.required]
}

# Google's minimal GKE node role includes logging and monitoring permissions.
# Additive binding: never take ownership of the shared project's IAM policy.
resource "google_project_iam_member" "node_permissions" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_artifact_registry_repository_iam_member" "image_pull" {
  for_each   = var.artifact_registry_repositories
  project    = each.value.project_id
  location   = each.value.location
  repository = each.value.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.nodes.email}"
  depends_on = [google_project_service.required]
}

# Retrieve the GKE service agent explicitly so a first cluster can use CMEK.
resource "google_project_service_identity" "gke" {
  provider   = google-beta
  project    = var.project_id
  service    = "container.googleapis.com"
  depends_on = [google_project_service.required]
}

resource "google_kms_crypto_key_iam_member" "secrets" {
  count         = var.database_encryption_key == null ? 0 : 1
  crypto_key_id = var.database_encryption_key
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.gke.email}"
}

resource "google_container_cluster" "this" {
  project             = var.project_id
  name                = var.cluster_name
  location            = var.region
  description         = "Regional production GKE Standard cluster managed by OpenTofu"
  deletion_protection = var.deletion_protection
  # Omitting enable_autopilot selects Standard; setting even false conflicts
  # with Standard-only arguments in the Google provider.

  network    = data.google_compute_network.existing.self_link
  subnetwork = data.google_compute_subnetwork.existing.self_link

  # GKE requires a bootstrap pool. OpenTofu removes it after creation.
  remove_default_node_pool = true
  initial_node_count       = 1
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    image_type      = "COS_CONTAINERD"
    metadata = {
      disable-legacy-endpoints = "true"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.private_endpoint
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
        display_name = cidr_blocks.value.name
        cidr_block   = cidr_blocks.value.cidr
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  enable_shielded_nodes = true
  enable_legacy_abac    = false
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  # Dataplane V2 provides NetworkPolicy enforcement. Do not also set legacy Calico.
  datapath_provider         = "ADVANCED_DATAPATH"
  default_max_pods_per_node = 32

  release_channel {
    channel = "REGULAR"
  }
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = var.maintenance_recurrence
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
    managed_prometheus {
      enabled = true
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
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }
  database_encryption {
    state    = var.database_encryption_key == null ? "DECRYPTED" : "ENCRYPTED"
    key_name = var.database_encryption_key
  }
  resource_labels = local.labels

  lifecycle {
    precondition {
      condition     = var.private_endpoint || length(var.authorized_networks) > 0
      error_message = "A public API endpoint requires explicit authorized_networks."
    }
    precondition {
      condition     = data.google_compute_subnetwork.existing.network == data.google_compute_network.existing.self_link
      error_message = "The existing GKE subnet must belong to the selected environment VPC."
    }
    precondition {
      condition     = alltrue([for name in ["pods", "services"] : contains([for range in data.google_compute_subnetwork.existing.secondary_ip_range : range.range_name], name)])
      error_message = "The network team must provision pods and services secondary ranges on the GKE subnet."
    }
    precondition {
      condition     = data.google_compute_subnetwork.existing.private_ip_google_access
      error_message = "Private nodes require Private Google Access on the existing subnet. Ask the network team to enable it."
    }
  }

  depends_on = [
    google_project_service.required,
    google_project_service_identity.gke,
    google_project_iam_member.node_permissions,
    google_kms_crypto_key_iam_member.secrets,
  ]
}

resource "google_container_node_pool" "this" {
  for_each = var.node_pools
  project  = var.project_id
  cluster  = google_container_cluster.this.name
  location = var.region
  name     = each.key

  # One node per default zone at creation; the autoscaler owns subsequent counts.
  initial_node_count = 1
  max_pods_per_node  = each.value.max_pods_per_node
  autoscaling {
    total_min_node_count = each.value.min_count
    total_max_node_count = each.value.max_count
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
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = "pd-balanced"
    image_type      = "COS_CONTAINERD"
    spot            = false
    preemptible     = false
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = merge(each.value.labels, local.labels)
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
  depends_on = [google_project_iam_member.node_permissions, google_artifact_registry_repository_iam_member.image_pull]
}

resource "google_service_account" "workload" {
  for_each     = var.workload_identities
  project      = var.project_id
  account_id   = each.key
  display_name = "GKE ${var.cluster_name} workload ${each.key}"
  depends_on   = [google_project_service.required]
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each           = var.workload_identities
  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.service_account}]"
  depends_on         = [google_container_cluster.this]
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_role_bindings
  project  = var.project_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.workload[each.value.account].email}"
}
