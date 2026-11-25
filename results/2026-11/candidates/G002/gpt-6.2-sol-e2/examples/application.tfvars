environment      = "staging"
instance_name    = "orders-postgres-staging"
region           = "us-central1"
database_version = "POSTGRES_16"
tier             = "db-custom-2-7680"

initial_disk_size_gb = 50

maintenance_window = {
  day  = 7
  hour = 5
}

databases = {
  orders = {}
}

iam_user_emails            = ["dba@example.com"]
iam_service_account_emails = ["orders-app@example-project.iam.gserviceaccount.com"]
