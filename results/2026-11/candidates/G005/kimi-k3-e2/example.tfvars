# A fuller example: production cluster in apps-prod with a general-purpose
# pool, a fixed-size pool, and a tainted spot pool for batch workloads.
# (Not used by default — see minimal.tfvars for the smallest instantiation.)

name                   = "platform-prod"
region                 = "us-central1"
network                = "apps-staging"
master_ipv4_cidr_block = "172.16.0.16/28"

labels = {
  env  = "prod"
  team = "platform"
}

master_authorized_networks = [
  { cidr_block = "10.0.0.0/8", display_name = "corp-vpn" },
]

node_pools = {
  default = {
    machine_type = "n2-standard-8"
    max_count    = 10
  }
  ingress = {
    autoscaling = false
    node_count  = 1
    labels      = { role = "ingress" }
    tags        = ["ingress"]
  }
  batch = {
    spot         = true
    machine_type = "e2-standard-4"
    min_count    = 0
    max_count    = 20
    taints       = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
  }
}
