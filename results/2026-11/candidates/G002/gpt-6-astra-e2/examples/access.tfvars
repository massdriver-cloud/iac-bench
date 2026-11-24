project_id       = "dba-platform-dev"
region           = "us-central1"
instance_name    = "dba-postgres-dev"
environment      = "dev"
database_version = "POSTGRES_16"
tier             = "db-custom-2-7680"

databases = {
  orders = {}
}
iam_members = {
  "dba@example.com"                                 = "USER"
  "orders@dba-platform-dev.iam.gserviceaccount.com" = "SERVICE_ACCOUNT"
  "database-readers@example.com"                    = "GROUP"
}
