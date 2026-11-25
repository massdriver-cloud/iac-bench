# Example of a fuller production instantiation (also exercises the optional
# module features). Adjust project/CIDRs/KMS key before real use.

project_id   = "platform-clusters-prod"
environment  = "prod"
region       = "us-east1"
cluster_name = "prod-shared-1"

master_authorized_networks = [
  {
    cidr_block   = "198.51.100.0/24"
    display_name = "platform-vpn"
  },
  {
    cidr_block   = "192.0.2.64/26"
    display_name = "bastion-subnet"
  },
]

master_ipv4_cidr_block  = "172.16.1.0/28"
enable_private_endpoint = false
release_channel         = "REGULAR"

primary_node_pool = {
  machine_type   = "e2-standard-8"
  min_node_count = 2
  max_node_count = 6
  disk_size_gb   = 200
  disk_type      = "pd-ssd"
}

extra_node_pools = {
  batch-spot = {
    machine_type   = "e2-standard-4"
    min_node_count = 0
    max_node_count = 10
    spot           = true
    taints = [
      { key = "workload", value = "batch", effect = "NO_SCHEDULE" },
    ]
  }
}

# Keyless access to Google Cloud services for product-team workloads.
workload_identities = {
  orders-api = {
    namespace = "orders"
    ksa_name  = "orders-api"
    roles = [
      "roles/pubsub.subscriber",
      "roles/pubsub.publisher",
      "roles/cloudsql.client",
    ]
  }
  reports-reader = {
    namespace = "reports"
    ksa_name  = "reports"
    roles = [
      "roles/storage.objectViewer",
    ]
  }
}

maintenance_start_time = "05:00"
maintenance_exclusions = {
  launch-freeze = {
    start_time = "2025-11-25T00:00:00Z"
    end_time   = "2025-12-03T00:00:00Z"
  }
}

enable_backup      = true
backup_retain_days = 30

database_encryption = {
  key_name = "projects/platform-clusters-prod/locations/us-east1/keyRings/gke/cryptoKeys/gke-secrets"
}

resource_labels = {
  cost-center = "platform"
}

# Keep the module default (true) for real production clusters.
