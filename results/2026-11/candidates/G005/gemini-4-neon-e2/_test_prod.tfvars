# Example production cluster configuration demonstrating optional customizations
# (not auto-loaded by OpenTofu; pass explicitly with -var-file if desired).

project_id   = "iacbench-sandbox"
cluster_name = "apps-prod-us-central1"
environment  = "prod"
region       = "us-central1"

authorized_networks = [
  { cidr_block = "203.0.113.0/24", display_name = "corporate-vpn" }
]

security_group = "gke-security-groups@example.com"

workload_node_pools = {
  general = {
    machine_type       = "n2-standard-4"
    min_count_per_zone = 2
    max_count_per_zone = 10
    upgrade_strategy   = "BLUE_GREEN"
  }
  sandbox = {
    machine_type       = "n2-standard-4"
    min_count_per_zone = 0
    max_count_per_zone = 4
    enable_gvisor      = true
  }
  batch-spot = {
    machine_type       = "e2-standard-8"
    min_count_per_zone = 0
    max_count_per_zone = 10
    spot               = true
  }
}
