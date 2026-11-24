data "google_client_config" "current" {}

data "google_compute_network" "vpc" {
  name = local.vpc_network_name
}
