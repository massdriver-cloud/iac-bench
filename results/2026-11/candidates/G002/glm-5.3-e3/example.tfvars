# A fully-decided instance, for reference. Everything here is optional
# except the seven required variables; `minimal.tfvars` is the same module
# with nothing but those.
#
#   tofu plan -var-file=example.tfvars

name             = "orders"
project          = "acme-apps"
environment      = "staging"
region           = "us-central1"
network          = "apps-staging"
database_version = "POSTGRES_16"
tier             = "db-custom-4-16384"

# The rest: standard defaults, overridden where this instance needs it.
zone                  = "us-central1-a"
availability_type     = "REGIONAL"
disk_size_gb          = 200
disk_autoresize_limit = 500
backup_start_time     = "03:00"
backup_retention_days = 30
kms_key_name          = "projects/acme-apps/locations/us-central1/keyRings/sql/cryptoKeys/staging"

maintenance_window = {
  day          = 3
  hour         = 2
  update_track = "week5"
}

databases = ["orders", "orders_archive"]

database_flags = {
  "max_connections"            = "400"
  "work_mem"                   = "64MB"
  "log_min_duration_statement" = "500"
}

iam_users = {
  # People default to CLOUD_IAM_USER.
  "alice@example.com" = {}

  # Workload identities on GKE / Compute Engine.
  "orders-api@acme-apps.iam.gserviceaccount.com" = { type = "CLOUD_IAM_SERVICE_ACCOUNT" }
}

labels = {
  team        = "dba"
  cost_center = "1234"
}
