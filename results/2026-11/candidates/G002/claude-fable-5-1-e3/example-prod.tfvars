# Example of a fuller prod instantiation (not required by the module).
project_id  = "example-project"
name        = "orders-prod"
environment = "prod"
region      = "europe-west1"

network_project_id = "example-network-host"
tier               = "db-custom-4-16384"
retained_backups   = 30
backup_location    = "eu"

database_flags = {
  max_connections            = "400"
  log_min_duration_statement = "1000"
}

databases = {
  orders   = {}
  payments = { collation = "C" }
}

iam_users = [
  "dba@example.com",
  "orders-api@example-project.iam.gserviceaccount.com",
]

labels = {
  team = "orders"
}
