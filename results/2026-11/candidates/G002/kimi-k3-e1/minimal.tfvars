# Smallest valid instantiation of the module: the DBA-owned decisions plus
# one database and the two kinds of IAM login. Everything else falls back to
# the organizational standards.

project_id = "example-project"
region     = "europe-west1"
network    = "apps-dev"

name = "pg-example-dev"
tier = "db-custom-2-7680"

databases = {
  app = {}
}

iam_users = [
  "alex.dba@example.com",
]

iam_service_accounts = [
  "app-runtime@example-project.iam.gserviceaccount.com",
]
