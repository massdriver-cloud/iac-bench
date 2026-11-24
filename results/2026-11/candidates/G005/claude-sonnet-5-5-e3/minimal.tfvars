project_id  = "my-project"
name        = "payments"
environment = "staging"
region      = "us-central1"

master_authorized_networks = [
  {
    cidr_block   = "10.0.0.0/8"
    display_name = "internal"
  }
]
