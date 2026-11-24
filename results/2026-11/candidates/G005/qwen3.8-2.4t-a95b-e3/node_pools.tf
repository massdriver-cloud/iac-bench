# The single general-purpose pool that product teams schedule onto.
#
# Design choices baked in by the module:
#  - regional pool: nodes land in every zone of the region automatically, so
#    a zone outage never takes the whole pool down
#  - surge upgrades (max_surge=1, max_unavailable=0): upgrades and repairs add
#    a node first and never reduce capacity mid-rollout
#  - auto-repair and auto-upgrade in line with the cluster's release channel
#  - autoscaling per zone, so every zone keeps capacity even while scaling
resource "google_container_node_pool" "primary" {
  provider = google

  project  = local.project_id
  name     = "primary"
  cluster  = google_container_cluster.this.name
  location = var.region

  initial_node_count = var.autoscaling_min_nodes_per_zone

  autoscaling {
    min_node_count = var.autoscaling_min_nodes_per_zone
    max_node_count = var.autoscaling_max_nodes_per_zone
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
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
    image_type   = "COS_CONTAINERD"

    # Dedicated, least-privilege node service account (see iam.tf) instead of
    # the Compute Engine default SA.
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Pods authenticate to Google APIs as their own IAM principals.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
