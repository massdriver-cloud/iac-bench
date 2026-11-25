# Smallest valid instantiation of the module.
# Only the cluster-specific inputs are required; everything else inherits the
# module's production defaults (regional us-central1 cluster, 1-3 nodes per
# zone, REGULAR release channel, Workload Identity, private nodes, etc.).

project_id   = "acme-apps-platform"
cluster_name = "apps-prod-central"
environment  = "prod"

# Unique /28 for this cluster's control plane inside apps-prod.
master_ipv4_cidr_block = "172.16.0.0/28"

# Platform team office/VPN egress range allowed to reach the API server.
master_authorized_networks = [
  {
    cidr_block   = "203.0.113.0/24"
    display_name = "platform-office"
  },
]
