# Mirror of minimal.tfvars so that a bare `tofu plan` also resolves the
# required inputs (an explicit -var-file=minimal.tfvars takes precedence).
project_id = "example-project-id"
region     = "us-central1"
name       = "pg-example-01"
network    = "apps-dev"
tier       = "db-custom-2-7680"
