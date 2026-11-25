project_id = "placeholder-project"
name       = "apps-prod-cluster"
location   = "us-central1"
network    = "apps-prod"
subnetwork = "apps-prod-gke-us-central1"

workload_identity_enabled = true

system_node_pool = {
  name               = "system"
  machine_type       = "e2-standard-4"
  initial_node_count = 1
  min_count          = 1
  max_count          = 3
}

workload_node_pools = {
  "general" = {
    machine_type = "e2-standard-4"
    min_count    = 1
    max_count    = 6
  }
}