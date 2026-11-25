project_id   = "apps-platform-123456"
region       = "us-central1"
environment  = "staging"
cluster_name = "apps-staging-us-central1"

master_authorized_networks = [
  {
    cidr_block   = "10.0.0.0/8"
    display_name = "corporate-vpn"
  }
]
