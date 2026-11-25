data "google_project" "current" {
  project_id = var.project_id
}

data "google_compute_network" "vpc" {
  name    = local.vpc_name
  project = var.project_id
}

data "google_compute_subnetwork" "gke" {
  name    = local.subnet_name
  region  = var.region
  project = var.project_id
}

# Verify the network team's subnet satisfies GKE VPC-native private cluster prerequisites.
check "gke_subnet_prerequisites" {
  assert {
    condition     = contains([for r in data.google_compute_subnetwork.gke.secondary_ip_range : r.range_name], local.pods_range_name)
    error_message = "Subnet '${local.subnet_name}' is missing required secondary IP range '${local.pods_range_name}'."
  }

  assert {
    condition     = contains([for r in data.google_compute_subnetwork.gke.secondary_ip_range : r.range_name], local.services_range_name)
    error_message = "Subnet '${local.subnet_name}' is missing required secondary IP range '${local.services_range_name}'."
  }

  assert {
    condition     = data.google_compute_subnetwork.gke.private_ip_google_access
    error_message = "Subnet '${local.subnet_name}' must have Private Google Access enabled so private GKE nodes can reach Google Cloud APIs (Artifact Registry, Logging, Monitoring, Pub/Sub, Cloud Storage, Cloud SQL)."
  }
}

# Optional firewall rule allowing a VPC-peered control plane to reach custom
# Kubernetes admission webhook ports (e.g., cert-manager, Kyverno, ingress-nginx).
# Private nodes communicate with Google APIs via Private Google Access, and
# general internet egress is handled by the network team's VPC Cloud NAT.
resource "google_compute_firewall" "control_plane_webhooks" {
  count = local.webhook_fw_enabled ? 1 : 0

  name        = "gke-${var.cluster_name}-webhooks"
  project     = var.project_id
  network     = data.google_compute_network.vpc.id
  direction   = "INGRESS"
  description = "Allow GKE control plane for ${var.cluster_name} to reach admission webhook ports on worker nodes."

  source_ranges = [var.master_ipv4_cidr_block]
  target_tags   = [local.cluster_network_tag]

  allow {
    protocol = "tcp"
    ports    = var.additional_control_plane_webhook_ports
  }
}
