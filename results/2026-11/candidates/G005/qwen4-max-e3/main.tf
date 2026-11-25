# ---------------------------------------------------------------------------
# Naming conventions owned by the network team:
#   VPC:     apps-<environment>
#   Subnet:  <vpc>-gke-<region>   (secondary ranges: "pods" and "services")
# Self links are constructed from the convention so the module does not depend
# on read-time lookups; the subnet must exist in var.project_id / var.region.
# ---------------------------------------------------------------------------

locals {
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"

  network_self_link    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_self_link = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  workload_identity_pool = "${var.project_id}.svc.id.goog"

  cluster_labels = merge(
    {
      environment = var.environment
      cluster     = var.cluster_name
      managed-by  = "opentofu"
    },
    var.resource_labels,
  )

  node_tags = ["gke-${var.cluster_name}-node"]

  # Least-privilege node service account: only what the kubelet / fluent-bit /
  # metadata agent need. Never roles/editor, never per-node key material.
  node_service_account_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]
}

resource "google_container_cluster" "this" {
  provider = google

  name     = var.cluster_name
  project  = var.project_id
  location = var.region # regional control plane + nodes across zones

  # --- Networking: VPC-native, in the network team's VPC/subnet -------------
  network    = local.network_self_link
  subnetwork = local.subnetwork_self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private nodes: no public IPs on workers; egress via Cloud NAT if needed.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = true
    }
  }

  # The control-plane endpoint is only reachable from explicitly listed CIDRs.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  enable_intranode_visibility = var.enable_intranode_visibility

  # Dataplane V2 (eBPF): built-in Kubernetes NetworkPolicy enforcement and
  # better network observability. Replaces the legacy network-policy addon.
  datapath_provider = "ADVANCED_DATAPATH"

  # --- Security posture ------------------------------------------------------
  enable_shielded_nodes = true
  enable_legacy_abac    = false

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = local.workload_identity_pool
  }

  binary_authorization {
    evaluation_mode = var.binary_authorization_evaluation_mode
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption == null ? [] : [var.database_encryption]
    content {
      state    = database_encryption.value.state
      key_name = database_encryption.value.key_name
    }
  }

  # --- Lifecycle: managed upgrades, no bespoke default pool ------------------
  release_channel {
    channel = var.release_channel
  }

  min_master_version = var.min_master_version

  # The default pool is removed immediately; all capacity comes from the
  # explicitly managed, secure node pools in node-pools.tf.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Node configuration for the short-lived default pool only; kept consistent
  # with the managed pools so nothing insecure ever runs, even briefly.
  node_config {
    image_type      = "COS_CONTAINERD"
    machine_type    = "e2-medium"
    disk_size_gb    = 50
    disk_type       = "pd-balanced"
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

  cluster_autoscaling {
    autoscaling_profile = "BALANCED"
  }

  # --- Operations: maintenance, logging, monitoring --------------------------
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }

    dynamic "maintenance_exclusion" {
      for_each = var.maintenance_exclusions
      content {
        exclusion_name = maintenance_exclusion.key
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time

        exclusion_options {
          scope = "NO_MINOR_UPGRADES"
        }
      }
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = var.enable_managed_prometheus
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
    # NetworkPolicy is enforced by Dataplane V2; the legacy addon must stay off.
    network_policy_config {
      disabled = true
    }
    # The Backup for GKE agent is required for backup plans to work.
    gke_backup_agent_config {
      enabled = var.enable_backup
    }
  }

  resource_labels = local.cluster_labels

  deletion_protection = var.deletion_protection

  lifecycle {
    # Version fields drift as GKE auto-upgrades through the release channel.
    ignore_changes = [
      min_master_version,
      node_version,
    ]
  }
}

# ---------------------------------------------------------------------------
# Optional disaster-recovery backups (Backup for GKE)
# ---------------------------------------------------------------------------

resource "google_gke_backup_backup_plan" "daily" {
  count = var.enable_backup ? 1 : 0

  name     = "${var.cluster_name}-daily"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.id

  retention_policy {
    backup_retain_days = var.backup_retain_days
  }

  backup_schedule {
    cron_schedule = "0 2 * * *"
  }

  backup_config {
    all_namespaces      = true
    include_volume_data = false
    include_secrets     = true
  }
}
