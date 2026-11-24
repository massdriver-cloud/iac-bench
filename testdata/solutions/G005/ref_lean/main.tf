data "google_project" "this" {}

locals {
  # The roles GKE documents for a minimal node service account.
  node_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]
}

resource "google_service_account" "nodes" {
  account_id   = substr("gke-nodes-${var.name}", 0, 30)
  display_name = "GKE nodes for ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_roles)
  project  = data.google_project.this.project_id
  role     = each.value
  member   = google_service_account.nodes.member
}

resource "google_container_cluster" "this" {
  name     = var.name
  location = var.region

  network    = var.network
  subnetwork = var.subnetwork

  # No default pool is ever created; the node pool below is the cluster's.
  initial_node_count  = 0
  deletion_protection = var.deletion_protection
  resource_labels     = var.labels

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # kubectl reaches the control plane only through its IAM-authenticated DNS
  # endpoint; the IP endpoints are off.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
    ip_endpoints_config {
      enabled = false
    }
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  addons_config {
    network_policy_config {
      disabled = false
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
      start_time = "2026-01-01T08:00:00Z"
      end_time   = "2026-01-01T12:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  dynamic "database_encryption" {
    for_each = var.secrets_encryption_key == null ? [] : [var.secrets_encryption_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "this" {
  name     = "general"
  cluster  = google_container_cluster.this.id
  location = var.region

  autoscaling {
    min_node_count = var.min_nodes_per_zone
    max_node_count = var.max_nodes_per_zone
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy = "BLUE_GREEN"
    blue_green_settings {
      node_pool_soak_duration = "1800s"
      standard_rollout_policy {
        batch_percentage    = 0.5
        batch_soak_duration = "60s"
      }
    }
  }

  network_config {
    enable_private_nodes = true
  }

  node_config {
    machine_type    = var.machine_type
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}
