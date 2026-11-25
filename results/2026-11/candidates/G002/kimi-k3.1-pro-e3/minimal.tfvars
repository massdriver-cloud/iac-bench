project_id        = "example-project"
instance_name     = "postgres-dev"
region            = "us-central1"
network_self_link = "projects/example-project/global/networks/apps-dev"

# Small, non-HA capacity for the smallest useful development instantiation.
machine_type      = "db-custom-1-3840"
availability_type = "ZONAL"
disk_size         = 10

labels = {
  environment = "dev"
  team        = "dba"
}

iam_users = {}
databases = {}
