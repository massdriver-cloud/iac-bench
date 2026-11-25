locals {
  vpc_name             = "apps-${var.environment}"
  network_self_link    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_name      = "${local.vpc_name}-gke-${var.region}"
  subnetwork_self_link = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnetwork_name}"

  cluster_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  required_apis = toset([
    "binaryauthorization.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "containerfilesystem.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = var.enable_required_apis ? local.required_apis : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  # Regional clusters provide a highly available control plane. The separately
  # managed node pools below are distributed across the same regional zones.
  network    = local.network_self_link
  subnetwork = local.subnetwork_self_link

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  default_max_pods_per_node = 64

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection
  resource_labels          = local.cluster_labels

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

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = var.master_global_access_enabled
    }
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [true] : []

    content {
      gcp_public_cidrs_access_enabled = false

      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          display_name = cidr_blocks.value.display_name
          cidr_block   = cidr_blocks.value.cidr_block
        }
      }
    }
  }

  # Dataplane V2 supplies network policy enforcement without the legacy Calico
  # add-on. Product teams still need to author default-deny NetworkPolicies.
  datapath_provider = "ADVANCED_DATAPATH"
  network_policy {
    enabled = true
  }
  enable_l4_ilb_subsetting = true

  enable_shielded_nodes = true
  enable_legacy_abac    = false

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

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
    dns_cache_config {
      enabled = true
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  # Node auto-provisioning is deliberately off. Capacity is autoscaled in the
  # explicit, policy-controlled node pools declared in node_pools.tf.
  cluster_autoscaling {
    enabled = false
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

  cost_management_config {
    enabled = true
  }

  dynamic "authenticator_groups_config" {
    for_each = var.authenticator_security_group == null ? [] : [var.authenticator_security_group]
    content {
      security_group = authenticator_groups_config.value
    }
  }

  dynamic "notification_config" {
    for_each = var.notification_pubsub_topic == null ? [] : [var.notification_pubsub_topic]
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  depends_on = [google_project_service.required]

  lifecycle {
    precondition {
      condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
      error_message = "A public control plane endpoint requires at least one entry in master_authorized_networks."
    }
  }
}
