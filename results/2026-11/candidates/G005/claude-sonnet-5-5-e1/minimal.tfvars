project_id  = "example-project"
name        = "apps-staging-1"
environment = "staging"
region      = "us-central1"

master_authorized_networks = {
  vpn = "10.100.0.0/24"
}
