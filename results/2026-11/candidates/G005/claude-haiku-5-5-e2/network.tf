locals {
  # Network team naming convention: one VPC per environment, one GKE subnet per region.
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"
}

data "google_compute_network" "apps" {
  project = var.project_id
  name    = local.vpc_name
}

data "google_compute_subnetwork" "gke" {
  project = var.project_id
  region  = var.region
  name    = local.subnet_name

  lifecycle {
    # GKE needs named secondary ranges for pods and services (VPC-native cluster).
    postcondition {
      condition     = contains([for r in self.secondary_ip_range : r.range_name], "pods")
      error_message = "Subnet ${local.subnet_name} must have a secondary range named \"pods\"."
    }

    postcondition {
      condition     = contains([for r in self.secondary_ip_range : r.range_name], "services")
      error_message = "Subnet ${local.subnet_name} must have a secondary range named \"services\"."
    }

    # Private nodes have no external IPs. Private Google Access lets them reach
    # Pub/Sub, Cloud Storage and other Google APIs without NAT or public IPs.
    postcondition {
      condition     = self.private_ip_google_access
      error_message = "Subnet ${local.subnet_name} must have Private Google Access enabled."
    }
  }
}
