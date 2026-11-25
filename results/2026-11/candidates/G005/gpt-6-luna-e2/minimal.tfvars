project_id             = "example-platform-prod"
cluster_name           = "apps-prod-us-central1"
region                 = "us-central1"
vpc_name               = "apps-prod"
master_ipv4_cidr_block = "172.16.0.0/28"
authorized_master_networks = [
  {
    cidr_block   = "203.0.113.10/32"
    display_name = "platform-access"
  }
]
