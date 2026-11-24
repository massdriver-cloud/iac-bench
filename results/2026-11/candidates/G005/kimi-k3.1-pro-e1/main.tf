locals {
  network_name    = "apps-${var.environment}"
  subnetwork_name = "${local.network_name}-gke-${var.region}"
  network_id      = "projects/${var.project_id}/global/networks/${local.network_name}"
  subnetwork_id   = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnetwork_name}"

  common_labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "opentofu"
    cluster     = var.cluster_name
  })

  required_services = toset(concat([
    "container.googleapis.com",
    "cloudkms.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    ], var.enable_binary_authorization ? [
    "binaryauthorization.googleapis.com"
    ] : [], var.enable_backup_agent ? [
    "gkebackup.googleapis.com"
  ] : []))

  node_service_account_roles = toset(concat([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ], tolist(var.additional_node_service_account_roles)))

  gke_service_agent = "service-${var.project_number}@container-engine-robot.iam.gserviceaccount.com"
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project                    = var.project_id
  service                    = each.key
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Enabling container.googleapis.com provisions this Google-managed identity.
# Its project role is granted non-authoritatively so other service agents and
# project IAM bindings are never replaced by this module.
resource "google_project_iam_member" "gke_service_agent" {
  project = var.project_id
  role    = "roles/container.serviceAgent"
  member  = "serviceAccount:${local.gke_service_agent}"

  depends_on = [google_project_service.required]
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${substr("gke-${var.cluster_name}", 0, 23)}-${substr(sha1(var.cluster_name), 0, 6)}"
  display_name = "GKE nodes for ${var.cluster_name}"
  description  = "Node infrastructure only; application credentials are issued through GKE Workload Identity."

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "nodes" {
  for_each = local.node_service_account_roles

  project = var.project_id
  role    = each.key
  member  = google_service_account.nodes.member
}

resource "google_kms_key_ring" "gke_secrets" {
  project  = var.project_id
  name     = "${var.cluster_name}-secrets"
  location = var.region

  depends_on = [google_project_service.required]
}

resource "google_kms_crypto_key" "gke_secrets" {
  name            = "etcd-secrets"
  key_ring        = google_kms_key_ring.gke_secrets.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s" # 90 days
  labels          = local.common_labels

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "gke_secrets" {
  crypto_key_id = google_kms_crypto_key.gke_secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.gke_service_agent}"

  depends_on = [google_project_service.required]
}

resource "google_pubsub_topic" "cluster_notifications" {
  project = var.project_id
  name    = "${var.cluster_name}-gke-notifications"
  labels  = local.common_labels

  depends_on = [google_project_service.required]
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  description = "Production GKE Standard cluster for the ${var.environment} environment"

  # A regional Standard cluster runs control-plane replicas and, by default, node
  # pools across multiple zones. The separately managed pools below replace the
  # insecure, non-production default node pool.
  initial_node_count       = 1
  remove_default_node_pool = true
  deletion_protection      = var.deletion_protection
  node_locations           = length(var.node_locations) > 0 ? sort(tolist(var.node_locations)) : null

  # These are references, not module-owned network resources. GKE resolves and
  # validates the subnet and its pods/services secondary ranges during apply.
  network    = local.network_id
  subnetwork = local.subnetwork_id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = var.enable_private_endpoint && var.enable_master_global_access
    }
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [true] : []
    content {
      gcp_public_cidrs_access_enabled = false

      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }
  min_master_version = var.min_master_version

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # The provider must briefly create a default pool before removing it. Do not
  # let even that transient pool fall back to the Compute Engine default identity
  # or to legacy node metadata behavior.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  enable_shielded_nodes    = true
  enable_legacy_abac       = false
  datapath_provider        = "ADVANCED_DATAPATH"
  enable_l4_ilb_subsetting = true

  # Dataplane V2 supplies Kubernetes NetworkPolicy enforcement without a
  # separately installed Calico daemonset.
  network_policy {
    enabled = true
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
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    gke_backup_agent_config {
      enabled = var.enable_backup_agent
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }

    advanced_datapath_observability_config {
      enable_metrics = true
      enable_relay   = false
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  # Autoscaling is deliberately managed per node pool; node auto-provisioning
  # would otherwise create pools outside the platform team's reviewed config.
  cluster_autoscaling {
    enabled             = false
    autoscaling_profile = "BALANCED"
  }

  database_encryption {
    state    = "ENCRYPTED"
    key_name = google_kms_crypto_key.gke_secrets.id
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  cost_management_config {
    enabled = true
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  notification_config {
    pubsub {
      enabled = true
      topic   = google_pubsub_topic.cluster_notifications.id

      filter {
        event_type = ["UPGRADE_EVENT", "SECURITY_BULLETIN_EVENT"]
      }
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group == null ? [] : [var.rbac_security_group]
    content {
      security_group = authenticator_groups_config.value
    }
  }

  resource_labels = local.common_labels

  lifecycle {
    precondition {
      condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
      error_message = "A public control-plane endpoint requires at least one master_authorized_networks CIDR; an unrestricted public endpoint is not supported."
    }
  }

  depends_on = [
    google_project_service.required,
    google_project_iam_member.gke_service_agent,
    google_kms_crypto_key_iam_member.gke_secrets,
    google_project_iam_member.nodes,
  ]

  timeouts {
    create = "45m"
    update = "60m"
    delete = "45m"
  }
}
