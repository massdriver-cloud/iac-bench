# ===========================================================================
# Plan-time probes of the network team's conventions
# ===========================================================================
#
# Before the cluster is created, probe the subnet the cluster will attach to
# (name derived from the <vpc>-gke-<region> convention) and verify it really
# carries the 'pods' and 'services' secondary ranges. A typo in vpc_name or
# region, or a missing secondary range, surfaces here with a pointed message
# instead of failing a long way into cluster creation. Checks never block a
# plan: if the subnet cannot be read (e.g. it does not exist), the failure is
# reported and the underlying error surfaces at apply time.

check "gke_subnet" {
  data "google_compute_subnetwork" "gke" {
    name   = local.subnet_name
    region = var.region
  }

  assert {
    condition = contains(
      [for secondary in data.google_compute_subnetwork.gke.secondary_ip_range : secondary.range_name],
      var.pods_secondary_range_name,
    )
    error_message = "Subnet ${local.subnet_name} has no secondary range named '${var.pods_secondary_range_name}' for pods; check vpc_name, region, subnet_name and pods_secondary_range_name."
  }

  assert {
    condition = contains(
      [for secondary in data.google_compute_subnetwork.gke.secondary_ip_range : secondary.range_name],
      var.services_secondary_range_name,
    )
    error_message = "Subnet ${local.subnet_name} has no secondary range named '${var.services_secondary_range_name}' for Services; check vpc_name, region, subnet_name and services_secondary_range_name."
  }
}
