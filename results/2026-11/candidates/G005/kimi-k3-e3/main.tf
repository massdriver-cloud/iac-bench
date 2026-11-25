locals {
  # The network team's subnet naming convention: <vpc>-gke-<region>.
  subnetwork = coalesce(var.subnetwork, "${var.network}-gke-${var.region}")
}

resource "google_container_cluster" "this" {
  name        = var.name
  description = "Managed by OpenTofu — the platform team's standard GKE module."
  project     = var.project_id
  location    = var.region

  # `location` is a region => regional cluster: three control-plane replicas
  # across zones, and node pools that span the region's zones by default.

  network    = var.network
  subnetwork = local.subnetwork

  # VPC-native routing onto the network team's pre-allocated secondary ranges.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Capacity is managed exclusively through the google_container_node_pool
  # resources in nodes.tf — never through the default node pool.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }
  min_master_version = var.kubernetes_version

  # --- Security posture -----------------------------------------------------

  enable_shielded_nodes = true

  # Workload Identity: Kubernetes service accounts impersonate Google service
  # accounts — no exported keys. This is how workloads on this cluster reach
  # Pub/Sub, Cloud Storage, Cloud SQL, etc.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private nodes: workers have no public IPs. The control plane keeps a
  # public endpoint unless enable_private_endpoint = true, and can be locked
  # to specific CIDRs with master_authorized_networks.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [true] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  dynamic "database_encryption" {
    for_each = var.secrets_encryption_key != null ? [var.secrets_encryption_key] : []
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  dynamic "binary_authorization" {
    for_each = var.binary_authorization_evaluation_mode != null ? [var.binary_authorization_evaluation_mode] : []
    content {
      evaluation_mode = binary_authorization.value
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group != null ? [var.rbac_security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # --- Networking -----------------------------------------------------------

  # Dataplane V2 (Cilium): kernel-level network policy enforcement without
  # the legacy Calico addon, plus more efficient Service handling.
  datapath_provider = "ADVANCED_DATAPATH"

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    dynamic "gcs_fuse_csi_driver_config" {
      for_each = var.enable_gcs_fuse_csi ? [true] : []
      content {
        enabled = true
      }
    }
  }

  # --- Operations -----------------------------------------------------------

  logging_config {
    enable_components = var.logging_components
  }

  monitoring_config {
    enable_components = var.monitoring_components

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }

    dynamic "maintenance_exclusion" {
      for_each = { for e in var.maintenance_exclusions : e.name => e }
      content {
        exclusion_name = maintenance_exclusion.value.name
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time

        dynamic "exclusion_options" {
          for_each = maintenance_exclusion.value.scope != null ? [maintenance_exclusion.value.scope] : []
          content {
            scope = exclusion_options.value
          }
        }
      }
    }
  }

  dynamic "notification_config" {
    for_each = var.upgrade_notification_topic != null ? [var.upgrade_notification_topic] : []
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  # Per-namespace / per-label cost breakdown — important on a cluster shared
  # by several product teams.
  cost_management_config {
    enabled = true
  }

  resource_labels = var.labels

  deletion_protection = var.deletion_protection
}
