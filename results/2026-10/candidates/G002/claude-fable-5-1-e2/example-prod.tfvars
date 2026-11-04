# Illustrative production instance. Everything not set here uses the module's
# environment-aware defaults (REGIONAL HA, 30 retained backups, etc.).
project_id         = "example-dba-project"
network_project_id = "example-network-host"
name               = "orders"
environment        = "prod"
region             = "europe-west1"

database_version = "POSTGRES_16"
tier             = "db-custom-4-16384"
disk_size_gb     = 100

database_flags = {
  max_connections            = "400"
  log_min_duration_statement = "1000"
}

databases = {
  orders  = {}
  billing = { collation = "C" }
}

iam_users = [
  "alice@example.com",
  "orders-api@example-apps-prod.iam.gserviceaccount.com",
]

iam_groups = [
  "dba-team@example.com",
]

break_glass_admin = "dba_admin"

labels = {
  team = "payments"
}
