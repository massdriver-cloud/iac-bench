project_id  = "apps-platform-project"
name        = "apps-prod-us-central1"
environment = "prod"
region      = "us-central1"

master_authorized_networks = [
  {
    cidr_block   = "203.0.113.0/24"
    display_name = "office-egress"
  },
]
