# The project the provider resolved: var.project_id if set, otherwise the
# project from the environment.
data "google_client_config" "current" {
  lifecycle {
    postcondition {
      condition     = self.project != null && self.project != ""
      error_message = "No project could be determined. Set var.project_id or export GOOGLE_PROJECT."
    }
  }
}

locals {
  project_id = data.google_client_config.current.project

  # Network-team conventions: one VPC per environment, one GKE subnet per
  # region named <vpc>-gke-<region>, with secondary ranges "pods" and "services".
  vpc_name            = "apps-${var.environment}"
  subnet_name         = "${local.vpc_name}-gke-${var.region}"
  network             = "projects/${local.project_id}/global/networks/${local.vpc_name}"
  subnetwork          = "projects/${local.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"
  pods_range_name     = "pods"
  services_range_name = "services"

  # Staging gets new GKE versions first; prod follows on the slower channel.
  release_channel = coalesce(var.release_channel, var.environment == "prod" ? "STABLE" : "REGULAR")

  # The date is only an anchor; the window recurs on the configured weekdays.
  maintenance_start = "2024-01-01T${var.maintenance_window.start_time}:00Z"
  maintenance_end   = timeadd(local.maintenance_start, "${var.maintenance_window.duration_hours}h")

  labels = merge(var.labels, {
    environment = var.environment
    cluster     = var.name
    managed-by  = "opentofu"
  })
}

resource "google_container_cluster" "this" {
  project     = local.project_id
  name        = var.name
  description = "Shared ${var.environment} cluster for product teams. Managed by the platform team with OpenTofu."

  # Regional: the control plane is replicated across the region's zones and
  # every node pool spreads its nodes across them.
  location = var.region

  deletion_protection = var.deletion_protection
  resource_labels     = local.labels

  # ---- Networking --------------------------------------------------------
  network         = local.network
  subnetwork      = local.subnetwork
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }

  # Dataplane V2 (eBPF). Enforces Kubernetes NetworkPolicy out of the box so
  # teams sharing the cluster can isolate their namespaces.
  datapath_provider = "ADVANCED_DATAPATH"

  # Nodes have no public IPs and the control plane has no public IP endpoint.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true

    master_global_access_config {
      enabled = true
    }
  }

  # Private IP endpoint: reachable only from the cluster's own nodes plus the
  # internal ranges listed here.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.control_plane_authorized_networks
      content {
        display_name = cidr_blocks.value.name
        cidr_block   = cidr_blocks.value.cidr
      }
    }
  }

  # DNS endpoint: how humans and CI reach the API server. Every request is
  # authenticated and authorised by Google Cloud IAM (container.clusters.connect)
  # before it reaches the control plane, so no bastion/VPN or IP allowlist is
  # needed.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
  }

  # ---- Upgrades ----------------------------------------------------------
  release_channel {
    channel = local.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = local.maintenance_start
      end_time   = local.maintenance_end
      recurrence = "FREQ=WEEKLY;BYDAY=${join(",", var.maintenance_window.days)}"
    }
  }

  # ---- Identity and access -------------------------------------------------
  # Workload Identity Federation for GKE: pods call Pub/Sub, Cloud Storage,
  # Cloud SQL etc. as their own Kubernetes service account, with no key files
  # and without borrowing the node's identity.
  workload_identity_config {
    workload_pool = "${local.project_id}.svc.id.goog"
  }

  enable_legacy_abac = false

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group == null ? [] : [var.rbac_security_group]
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # ---- Hardening ---------------------------------------------------------
  enable_shielded_nodes = true

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_DISABLED"
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  dynamic "database_encryption" {
    for_each = var.secrets_encryption_kms_key == null ? [] : [var.secrets_encryption_kms_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # ---- Add-ons -----------------------------------------------------------
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
    # NodeLocal DNSCache: DNS keeps answering through kube-dns restarts.
    dns_cache_config {
      enabled = true
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  # ---- Observability and cost ----------------------------------------------
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
      "STORAGE",
      "HPA",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
      "STATEFULSET",
    ]

    managed_prometheus {
      enabled = true
    }
  }

  # Per-namespace / per-label cost breakdown in Cloud Billing, so shared
  # cluster spend can be attributed to product teams.
  cost_management_config {
    enabled = true
  }

  # ---- Node pools --------------------------------------------------------
  # GKE insists on creating a default pool with the cluster. It is deleted
  # straight away; real pools are google_container_node_pool.this. The
  # throwaway pool still runs as the dedicated node service account so nothing
  # ever depends on the Compute Engine default service account.
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    # The default pool no longer exists after creation; never let its settings
    # show up as drift (a change there would replace the whole cluster).
    ignore_changes = [node_config, initial_node_count]
  }

  timeouts {
    create = "60m"
    update = "90m"
    delete = "60m"
  }

  depends_on = [google_project_iam_member.nodes]
}
