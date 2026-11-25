# A production-flavoured instantiation of the module — every value here is a
# per-database decision; nothing contradicts the module's fixed policy.

name             = "orders-db"
region           = "us-central1"
environment      = "prod"
network          = "projects/example-project/global/networks/apps-prod"
tier             = "db-custom-8-30720"
database_version = "POSTGRES_17"

zone         = "us-central1-a"
disk_size_gb = 500
edition      = "ENTERPRISE"

backup_start_time     = "03:00"
backup_retention_days = 35

maintenance_window = {
  day          = 7
  hour         = 3
  update_track = "stable"
}

database_flags = {
  max_connections = "400"
  work_mem        = "64MB"
}

databases = {
  orders    = {}
  analytics = { collation = "en_US.UTF8" }
}

iam_users = [
  "alice@example.com",
  "bob@example.com",
]

iam_service_accounts = [
  "orders-api@example-project.iam.gserviceaccount.com",
  "orders-migrations@example-project.iam.gserviceaccount.com",
]

read_replicas = {
  "orders-db-read-us" = {
    tier   = "db-custom-4-15360"
    region = "us-central1"
  }
  "orders-db-read-eu" = {
    tier         = "db-custom-4-15360"
    region       = "europe-west1"
    disk_size_gb = 300
  }
}

kms_key_name = "projects/example-project/locations/us-central1/keyRings/db/cryptoKeys/orders"

labels = {
  team    = "orders"
  service = "orders-api"
}
