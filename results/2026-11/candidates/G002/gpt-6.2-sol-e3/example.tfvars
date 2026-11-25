instance_name    = "dba-staging-postgres"
environment      = "staging"
region           = "us-central1"
database_version = "POSTGRES_16"
tier             = "db-custom-2-7680"

availability_type = "REGIONAL"
maintenance_window = {
  day  = 7
  hour = 5
}

databases = {
  application = {}
}

iam_users            = ["dba@example.com"]
iam_service_accounts = ["app-runtime@example-project.iam.gserviceaccount.com"]
