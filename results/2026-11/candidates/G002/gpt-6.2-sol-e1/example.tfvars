# Replace the instance ID, location, sizing, and identity emails before use.
environment      = "prod"
instance_name    = "ledger-postgres-prod"
region           = "us-central1"
database_version = "POSTGRES_16"
tier             = "db-custom-2-7680"

maintenance_window = { day = 7, hour = 5 }
database_flags     = { log_min_duration_statement = "1000" }
labels             = { application = "ledger" }

databases = {
  ledger = {}
}

iam_database_users = {
  "dba@example.com"                                    = "CLOUD_IAM_USER"
  "ledger-api@example-project.iam.gserviceaccount.com" = "CLOUD_IAM_SERVICE_ACCOUNT"
  "ledger-readers@example.com"                         = "CLOUD_IAM_GROUP"
}
