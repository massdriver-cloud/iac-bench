data "google_project" "this" {}

locals {
  project_id     = data.google_project.this.project_id
  project_number = data.google_project.this.number

  # Network team conventions: one VPC per environment, one GKE subnet per
  # region, fixed secondary range names.
  vpc_name             = "apps-${var.environment}"
  subnet_name          = "${local.vpc_name}-gke-${var.region}"
  pods_range_name      = "pods"
  services_range_name  = "services"
  workload_pool        = "${local.project_id}.svc.id.goog"
  gke_service_agent    = "serviceAccount:service-${local.project_number}@container-engine-robot.iam.gserviceaccount.com"
  release_channel      = coalesce(var.release_channel, var.environment == "prod" ? "STABLE" : "REGULAR")
  create_secrets_key   = var.secrets_encryption_kms_key == null
  secrets_kms_key_name = local.create_secrets_key ? google_kms_crypto_key.secrets[0].id : var.secrets_encryption_kms_key

  labels = merge(var.labels, {
    environment = var.environment
    cluster     = var.name
    managed-by  = "opentofu"
  })
}

# Short random suffix for project-global names (service account, key ring) so
# two clusters with the same name in different regions do not collide, and a
# cluster can be recreated even though KMS key rings can never be deleted.
resource "random_id" "suffix" {
  byte_length = 2
}

# APIs the module needs. Never disabled on destroy: other clusters and
# workloads in the project use them too.
resource "google_project_service" "container" {
  project            = local.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_container_cluster" "this" {
  project     = local.project_id
  name        = var.name
  description = "${var.environment} GKE Standard cluster managed by the platform team's OpenTofu module."

  # Regional cluster: replicated control plane and nodes spread over several
  # zones, so neither a zone outage nor a control plane upgrade is downtime.
  location       = var.region
  node_locations = var.zones

  deletion_protection = var.deletion_protection

  # --- Network: the network team's VPC and GKE subnet -----------------------
  network           = data.google_compute_subnetwork.gke.network
  subnetwork        = data.google_compute_subnetwork.gke.self_link
  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH" # Dataplane V2: NetworkPolicy is enforced, which a shared cluster needs.

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }

  # --- Control plane access -------------------------------------------------
  # Nodes have no public IPs and the control plane has no public IP endpoint.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  # People and CI reach the API server through the DNS-based endpoint, where
  # every request is authenticated and authorised by IAM
  # (container.clusters.connect) before it reaches the cluster. No bastion,
  # VPN or IP allowlist to maintain.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
  }

  # The private IP endpoint only accepts the cluster's own ranges plus
  # whatever is listed explicitly.
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # No static credentials: no client certificate, no basic auth, no ABAC.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  enable_legacy_abac = false

  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group == null ? [] : [var.rbac_security_group]
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # --- Workload security ----------------------------------------------------
  # Workload Identity: pods call Pub/Sub, Cloud Storage, Cloud SQL etc. as
  # their Kubernetes service account. No service account key files.
  workload_identity_config {
    workload_pool = local.workload_pool
  }

  # Kubernetes Secrets are encrypted in etcd with a customer-managed key.
  database_encryption {
    state    = "ENCRYPTED"
    key_name = local.secrets_kms_key_name
  }

  enable_shielded_nodes = true

  node_pool_defaults {
    node_config_defaults {
      insecure_kubelet_readonly_port_enabled = "FALSE"
    }
  }

  # Free posture dashboard: flags workloads that run privileged, as root, etc.
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_DISABLED"
  }

  # --- Upgrades and maintenance ---------------------------------------------
  release_channel {
    channel = local.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = "2025-01-01T${var.maintenance_window.start_time_utc}:00Z"
      end_time   = "2025-01-01T${var.maintenance_window.end_time_utc}:00Z"
      recurrence = var.maintenance_window.recurrence
    }
  }

  # --- Observability and cost ------------------------------------------------
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER",
      "STORAGE", "POD", "DEPLOYMENT", "STATEFULSET", "DAEMONSET", "HPA",
    ]

    managed_prometheus {
      enabled = true
    }
  }

  # Per-namespace / per-label cost breakdown in Cloud Billing export, so the
  # shared cluster's cost can be attributed to product teams.
  cost_management_config {
    enabled = true
  }

  resource_labels = local.labels

  # --- Add-ons ---------------------------------------------------------------
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
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    dns_cache_config {
      enabled = true
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  # --- Node pools ------------------------------------------------------------
  # Node pools are separate resources (node_pools.tf) so they can be changed
  # without touching the cluster. GKE insists on creating a default pool; it
  # is created as small and as locked down as the real pools (in particular
  # NOT with the Compute Engine default service account) and removed at once.
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    machine_type    = "e2-medium"
    disk_size_gb    = 50
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

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

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  lifecycle {
    # The default pool no longer exists after creation; its settings must not
    # show up as drift (which would force the cluster to be replaced).
    ignore_changes = [node_config, initial_node_count]

    precondition {
      condition     = var.zones == null ? true : alltrue([for z in var.zones : startswith(z, "${var.region}-")])
      error_message = "Every entry in zones must be a zone of ${var.region} (for example ${var.region}-a)."
    }

    precondition {
      condition = alltrue(flatten([
        for _, p in var.node_pools : [for z in coalesce(p.zones, []) : startswith(z, "${var.region}-")]
      ]))
      error_message = "Every node pool zone must be a zone of ${var.region} (for example ${var.region}-a)."
    }
  }

  depends_on = [
    google_project_service.container,
    google_project_iam_member.nodes,
    time_sleep.secrets_key_iam_propagation,
  ]
}
