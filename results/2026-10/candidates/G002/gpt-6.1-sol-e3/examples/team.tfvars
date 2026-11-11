# Illustrative non-minimal configuration; replace project/network/identities before apply.
project_id        = "dba-platform-dev"
region            = "us-central1"
instance_name     = "postgres-dev"
network_self_link = "https://www.googleapis.com/compute/v1/projects/dba-platform-dev/global/networks/apps-dev"
postgres_version  = "POSTGRES_17"
tier              = "db-custom-2-7680"
databases         = ["orders"]
iam_principals = {
  "dba@example.com"                                 = "IAM_USER"
  "orders@dba-platform-dev.iam.gserviceaccount.com" = "IAM_SERVICE_ACCOUNT"
  "database-readers@example.com"                    = "IAM_GROUP"
}
database_flags = { max_connections = "150" }
labels         = { environment = "dev", team = "dba" }
