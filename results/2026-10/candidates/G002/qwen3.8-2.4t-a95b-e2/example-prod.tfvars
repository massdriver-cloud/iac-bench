# Example: a production database exercising the optional knobs. Not required —
# the module's defaults cover everything the brief mandates on its own.
project     = "acme-dba-postgres-prod"
name        = "orders"
environment = "prod"
region      = "us-central1"

tier                  = "db-custom-4-15360"
disk_size_gb          = 250
backup_retention_days = 35
# availability_type   = "REGIONAL" (default; the only value allowed in prod)
# deletion_protection = true       (default; cannot be disabled in prod)

database_flags = {
  work_mem                   = "65536" # kB
  max_connections            = "200"
  log_min_duration_statement = "1000" # ms
}

labels = {
  owner       = "dba"
  application = "orders"
}

iam_database_users = [
  "orders-svc@acme-dba-postgres-prod.iam.gserviceaccount.com",
  "dba-oncall@acme.example.com",
]
