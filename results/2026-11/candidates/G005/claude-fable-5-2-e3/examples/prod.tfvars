# A fuller production cluster: two zonal-spread pools, group-based RBAC and
# an extra private range allowed to reach the control plane's private IP.
name        = "shared-01"
environment = "prod"
region      = "us-central1"

node_pools = {
  general = {
    machine_type       = "n2-standard-8"
    min_nodes_per_zone = 2
    max_nodes_per_zone = 10
  }
  batch-spot = {
    machine_type       = "n2-standard-8"
    spot               = true
    min_nodes_per_zone = 0
    max_nodes_per_zone = 20
    labels             = { workload = "batch" }
    taints = [{
      key    = "workload"
      value  = "batch"
      effect = "NO_SCHEDULE"
    }]
  }
}

rbac_security_group = "gke-security-groups@example.com"

master_authorized_networks = [{
  cidr_block   = "10.200.0.0/24"
  display_name = "platform-ci-runners"
}]

labels = {
  cost-centre = "platform"
}
