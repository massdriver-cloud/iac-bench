# Smallest valid instantiation of the standard GKE module: the four inputs
# that identify the cluster, plus one workload node pool so product teams
# have capacity from day one. Everything else is a module default.
#
# Derived values for this instantiation:
#   cluster name: apps-prod-us-central1   (<vpc_name>-<region>)
#   subnet:       apps-prod-gke-us-central1 (<vpc_name>-gke-<region>, the
#                 network team's naming standard), secondary ranges 'pods'
#                 and 'services'.

project_id              = "acme-apps-prod"
region                  = "us-central1"
vpc_name                = "apps-prod"
control_plane_ipv4_cidr = "172.16.8.0/28"

node_pools = [
  {
    name         = "general"
    machine_type = "e2-standard-4"
    min_size     = 1
    max_size     = 5
  },
]
