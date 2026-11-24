project_id     = "example-dba-project"
name           = "apps-dev-postgres"
region         = "us-central1"
network        = "projects/example-dba-project/global/networks/apps-dev"
database_names = ["app"]
iam_identities = {
  "dba@example.com" = "USER"
}
