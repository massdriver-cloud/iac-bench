# A fuller, realistic instantiation: a staging instance. This file is only an
# example - it is not auto-loaded (only *.auto.tfvars would be); pass it
# explicitly with -var-file=example-staging.tfvars.

name        = "orders-db"
project_id  = "acme-apps-staging"
region      = "europe-west3"
environment = "staging"

major_version = "16"
tier          = "db-custom-4-15360"
edition       = "ENTERPRISE_PLUS"

databases            = ["orders", "orders_reporting"]
iam_service_accounts = ["orders-api@acme-apps-staging.iam.gserviceaccount.com"]
iam_users            = ["jane.doe@acme.com", "rafael.silva@acme.com"]

maintenance_window_day  = 7
maintenance_window_hour = 5
backup_start_time       = "02:30"

labels = {
  team = "dba"
  app  = "orders"
}
