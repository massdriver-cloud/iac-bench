project_id             = "example-apps-prod"
cluster_name           = "apps-prod-us1"
region                 = "us-central1"
environment            = "prod"
master_ipv4_cidr_block = "172.16.0.0/28"

master_authorized_networks = [
  {
    cidr_block   = "10.10.0.0/16"
    display_name = "platform-team-vpn"
  },
]
