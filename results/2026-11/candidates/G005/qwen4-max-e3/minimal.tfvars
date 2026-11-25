# Smallest valid instantiation of the platform GKE module.
# Everything not listed here uses the module's production-safe defaults.

project_id   = "platform-clusters-staging"
environment  = "staging"
region       = "us-central1"
cluster_name = "staging-shared-1"

# Control-plane access is restricted to the platform VPN range.
master_authorized_networks = [
  {
    cidr_block   = "203.0.113.0/24"
    display_name = "platform-vpn"
  },
]

# Disposable smoke-test instantiation; real production clusters keep the
# module default (deletion_protection = true).
deletion_protection = false
