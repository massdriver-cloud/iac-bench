name          = "orders"
project_id    = "example-project"
region        = "us-central1"
network_name  = "apps-dev"
environment   = "dev"
database_name = "orders"
users = {
  app_svc = "app-svc@example-project.iam.gserviceaccount.com"
}