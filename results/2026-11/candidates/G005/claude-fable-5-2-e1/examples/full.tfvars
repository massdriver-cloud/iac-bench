# Every knob the module has, for reference. Most clusters need only the three
# values in ../minimal.tfvars.

name        = "apps-prod-use4"
environment = "prod"
region      = "us-east4"

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
    taints = [
      { key = "workload", value = "batch", effect = "NO_SCHEDULE" },
    ]
  }
}

release_channel = "STABLE"

maintenance_window = {
  start_time     = "07:00"
  duration_hours = 4
  days           = ["TU", "WE", "TH"]
}

control_plane_authorized_networks = [
  { name = "ci-runners", cidr = "10.50.0.0/24" },
]

rbac_security_group         = "gke-security-groups@example.com"
secrets_encryption_kms_key  = "projects/example-security/locations/us-east4/keyRings/gke/cryptoKeys/apps-prod-secrets"
enable_binary_authorization = true

labels = {
  cost-centre = "platform"
}
