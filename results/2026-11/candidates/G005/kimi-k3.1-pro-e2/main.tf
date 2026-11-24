locals {
  network_name    = "apps-${var.environment}"
  subnetwork_name = "${local.network_name}-gke-${var.region}"

  network_self_link    = "projects/${var.project_id}/global/networks/${local.network_name}"
  subnetwork_self_link = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnetwork_name}"

  resource_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  generated_node_service_account_id = "${trim(substr("gke-${var.cluster_name}", 0, 24), "-")}-${substr(sha1(var.cluster_name), 0, 5)}"
  node_service_account_id           = coalesce(var.node_service_account_id, local.generated_node_service_account_id)

  required_apis = setunion(
    toset([
      "artifactregistry.googleapis.com",
      "compute.googleapis.com",
      "container.googleapis.com",
      "iam.googleapis.com",
      "iamcredentials.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com",
    ]),
    var.upgrade_notification_topic == null ? toset([]) : toset(["pubsub.googleapis.com"])
  )
}

resource "google_project_service" "required" {
  for_each = var.enable_apis ? local.required_apis : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_container_cluster" "this" {
  name        = var.cluster_name
  description = "Production ${var.environment} cluster managed by the platform team"
  project     = var.project_id
  location    = var.region

  network    = local.network_self_link
  subnetwork = local.subnetwork_self_link

  # Nodes are managed only in google_container_node_pool resources below. One
  # temporary node per zone is requested solely because GKE requires an initial
  # pool at creation; that default pool is removed immediately.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection
  resource_labels     = local.resource_labels
  enable_legacy_abac  = false

  # A regional location provides a multi-replica control plane and spreads the
  # default node pool locations across zones in the region.
  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH"

  # Dataplane V2 provides Kubernetes NetworkPolicy enforcement. The legacy
  # Calico network_policy block is deliberately not enabled with this datapath.
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
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
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  service_external_ips_config {
    enabled = false
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

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

    dns_cache_config {
      enabled = true
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  logging_config {
    enable_components = sort(tolist(var.logging_components))
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = var.managed_prometheus_enabled
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.gke_security_group == null ? [] : [true]

    content {
      security_group = var.gke_security_group
    }
  }

  dynamic "notification_config" {
    for_each = var.upgrade_notification_topic == null ? [] : [true]

    content {
      pubsub {
        enabled = true
        topic   = var.upgrade_notification_topic
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
      error_message = "A public control-plane endpoint requires at least one master authorized network. Keep enable_private_endpoint=true or supply master_authorized_networks."
    }

    precondition {
      condition     = var.enable_private_endpoint || !var.master_global_access_enabled
      error_message = "master_global_access_enabled applies only when the control plane has a private-only endpoint."
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name           = each.key
  project        = var.project_id
  location       = var.region
  cluster        = google_container_cluster.this.name
  node_locations = length(each.value.node_locations) > 0 ? each.value.node_locations : null

  max_pods_per_node = each.value.max_pods_per_node

  autoscaling {
    min_node_count  = each.value.min_nodes
    max_node_count  = each.value.max_nodes
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Surge upgrades keep existing capacity available while replacement nodes
  # become healthy. Ensure the project has quota for one extra node per pool.
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    image_type   = "COS_CONTAINERD"
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    spot         = each.value.spot

    service_account = google_service_account.nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = merge({
      environment = var.environment
      node-pool   = each.key
    }, each.value.labels)
    resource_labels = local.resource_labels
    tags            = each.value.network_tags

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

    dynamic "taint" {
      for_each = each.value.taints

      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  depends_on = [google_project_iam_member.node]
}
