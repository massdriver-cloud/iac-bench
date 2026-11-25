project_id             = "example-platform-prod"
cluster_name           = "products-prod"
environment            = "prod"
region                 = "us-central1"
master_ipv4_cidr_block = "172.20.0.0/28"
control_plane_authorized_cidrs = {
  platform-runners = "10.10.0.0/24"
}
