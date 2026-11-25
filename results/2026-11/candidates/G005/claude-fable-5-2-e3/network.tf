# The VPC and its GKE subnets belong to the network team; this module only
# looks them up. Doing it as a data source means a wrong environment/region,
# or a subnet that is not ready for GKE, fails at plan time with a clear
# message instead of twenty minutes into cluster creation.
data "google_compute_subnetwork" "gke" {
  project = local.project_id
  name    = local.subnet_name
  region  = var.region

  lifecycle {
    postcondition {
      condition     = self.network != null && endswith(coalesce(self.network, "-"), "/global/networks/${local.vpc_name}")
      error_message = "Subnet ${local.subnet_name} was not found in VPC ${local.vpc_name} in ${var.region}. Ask the network team whether the GKE subnet exists for this environment and region."
    }

    postcondition {
      condition = length(setsubtract(
        [local.pods_range_name, local.services_range_name],
        [for r in coalesce(self.secondary_ip_range, []) : r.range_name]
      )) == 0
      error_message = "Subnet ${local.subnet_name} must have secondary ranges named \"${local.pods_range_name}\" and \"${local.services_range_name}\"."
    }
  }
}

# Nodes have no public IPs. Without Private Google Access they cannot pull
# images from Artifact Registry or reach Google APIs unless all of that goes
# through Cloud NAT. Not fatal, so a warning rather than an error.
check "subnet_private_google_access" {
  assert {
    condition     = data.google_compute_subnetwork.gke.private_ip_google_access == true
    error_message = "Subnet ${local.subnet_name} does not have Private Google Access enabled. Private nodes need it (or Cloud NAT) to pull images and call Google APIs; ask the network team to enable it."
  }
}
