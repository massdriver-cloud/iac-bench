# A different good design: an Autopilot cluster, where Google manages nodes,
# so node hardening, autoscaling and node pools are the platform's job, with
# a smaller interface, provider configuration from the environment, and the
# network and subnet passed in by name.

variable "name" {
  description = "Cluster name."
  type        = string
}

variable "region" {
  description = "Region for the cluster."
  type        = string
}

variable "network" {
  description = "VPC network name (apps-staging or apps-prod)."
  type        = string
}

variable "subnetwork" {
  description = "GKE subnet name in the region; must carry secondary ranges named pods and services."
  type        = string
}

variable "deletion_protection" {
  description = "Refuse to destroy the cluster."
  type        = bool
  default     = true
}

data "google_client_config" "this" {}

resource "google_service_account" "nodes" {
  account_id   = substr("gke-${var.name}", 0, 30)
  display_name = "GKE Autopilot nodes for ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  project = data.google_client_config.this.project
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.nodes.member
}

resource "google_container_cluster" "this" {
  name                = var.name
  location            = var.region
  enable_autopilot    = true
  deletion_protection = var.deletion_protection

  network    = "projects/${data.google_client_config.this.project}/global/networks/${var.network}"
  subnetwork = "projects/${data.google_client_config.this.project}/regions/${var.region}/subnetworks/${var.subnetwork}"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  master_authorized_networks_config {}

  release_channel {
    channel = "STABLE"
  }

  maintenance_policy {
    recurring_window {
      start_time = "2026-01-01T09:00:00Z"
      end_time   = "2026-01-01T13:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=TU,WE,TH"
    }
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.nodes.email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  depends_on = [google_project_iam_member.nodes]
}

output "cluster_id" {
  description = "Cluster resource ID."
  value       = google_container_cluster.this.id
}
