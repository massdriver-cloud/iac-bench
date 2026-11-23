data "google_project" "this" {}

data "google_compute_network" "env" {
  name = "apps-${var.environment}"
}

data "google_compute_subnetwork" "gke" {
  name   = "apps-${var.environment}-gke-${var.region}"
  region = var.region
}

resource "google_service_account" "nodes" {
  account_id   = substr("gke-${var.name}", 0, 30)
  display_name = "GKE nodes for ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  project = data.google_project.this.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.nodes.member
}

resource "google_container_cluster" "this" {
  name     = var.name
  location = var.region

  network    = data.google_compute_network.env.self_link
  subnetwork = data.google_compute_subnetwork.gke.self_link

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection
  datapath_provider        = "ADVANCED_DATAPATH"
  enable_shielded_nodes    = true

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        display_name = cidr_blocks.key
        cidr_block   = cidr_blocks.value
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = "${data.google_project.this.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
  }

  dynamic "database_encryption" {
    for_each = var.secrets_encryption_key == null ? [] : [var.secrets_encryption_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group == null ? [] : [var.rbac_security_group]
    content {
      security_group = authenticator_groups_config.value
    }
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  cost_management_config {
    enabled = true
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  addons_config {
    gke_backup_agent_config {
      enabled = true
    }
  }

  node_pool_defaults {
    node_config_defaults {
      gcfs_config {
        enabled = true
      }
    }
  }

  # The default pool is removed after creation; its settings only have to be
  # valid for the moment it exists.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    shielded_instance_config {
      enable_secure_boot = true
    }
  }

  depends_on = [google_project_iam_member.nodes]

  lifecycle {
    ignore_changes = [node_config]
  }
}

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  cluster  = google_container_cluster.this.id
  location = var.region

  autoscaling {
    min_node_count = each.value.min_nodes
    max_node_count = each.value.max_nodes
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
    spot            = each.value.spot
    labels          = each.value.labels
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}
