name               = "postgres-core-db"
project_id         = "apps-prod"
region             = "us-central1"
network_name       = "apps-prod"
allocated_ip_range = "google-managed-services-apps-prod"

databases = {
  app = "UTF8"
}

iam_users = {
  app = [
    "user:dba.lead@example.com",
    "serviceAccount:app-svc@app-prod.iam.gserviceaccount.com",
  ]
}

environment = "prod"