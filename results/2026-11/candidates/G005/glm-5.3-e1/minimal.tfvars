# Smallest valid instantiation of the GKE Standard module: only the inputs
# that are genuinely per-cluster. Everything else runs on the module's
# production defaults (see variables.tf and README.md).

project_id  = "acme-platform"
name        = "shared-usc1"
region      = "us-central1"
environment = "prod"

# Networks allowed to talk to the Kubernetes API server (documentation range).
master_authorized_networks = {
  platform-vpn = "203.0.113.0/24"
}
