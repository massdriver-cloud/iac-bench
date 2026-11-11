# A fuller instantiation, for reference:
#   tofu plan -var-file=examples/prod.tfvars

project_id       = "example-project"
name             = "orders"
environment      = "prod"
region           = "europe-west1"
database_version = "POSTGRES_16"

tier                     = "db-custom-8-32768"
disk_size_gb             = 200
disk_autoresize_limit_gb = 1000
zone                     = "europe-west1-b"

databases = ["orders", "orders_reporting"]

database_flags = {
  "max_connections"            = "400"
  "log_min_duration_statement" = "500"
}

iam_groups           = ["dba-team@example.com", "orders-engineers@example.com"]
iam_users            = ["alex@example.com"]
iam_service_accounts = ["orders-api@example-project.iam.gserviceaccount.com"]

backup_start_time      = "01:00"
backup_retention_count = 60
maintenance_window = {
  day  = 6
  hour = 23
}

labels = {
  team = "orders"
}
