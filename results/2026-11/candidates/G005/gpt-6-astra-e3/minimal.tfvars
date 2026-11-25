project_id             = "platform-prod-example"
cluster_name           = "prod-us-central1"
environment            = "prod"
region                 = "us-central1"
master_ipv4_cidr_block = "172.20.0.0/28"
authorized_networks = [
  { name = "platform-admin-private", cidr = "10.10.0.0/24" }
]
