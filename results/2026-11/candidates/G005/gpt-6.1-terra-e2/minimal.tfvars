project_id             = "example-platform-prod"
environment            = "prod"
region                 = "us-central1"
cluster_name           = "production"
master_ipv4_cidr_block = "172.20.0.0/28"
master_authorized_networks = [
  {
    display_name = "platform-vpn"
    cidr_block   = "203.0.113.0/24"
  }
]
