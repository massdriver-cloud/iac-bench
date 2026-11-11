# Smallest valid instantiation of the module: the required variables plus the
# one policy override that ephemeral environments need. Everything else runs
# on the module's standards: POSTGRES_16, private IP only (apps-dev already
# has private services access), TLS required, IAM database authentication,
# daily backups with point-in-time recovery, Query Insights, deletion
# protection.

project_id = "apps-dev-42"
region     = "us-central1"
name       = "apps-dev-pg"
network    = "apps-dev"
tier       = "db-custom-1-3840"

# The module default (true) protects real environments; throwaway instances
# need this false so they can be destroyed cleanly.
deletion_protection = false

# Access is granted to Google identities only: one engineer, and one GKE
# workload that connects through the Cloud SQL connector.
iam_users = {
  "dba@example.com" = {}
  "gke-app@apps-dev-42.iam.gserviceaccount.com" = {
    grant_cloudsql_client = true
  }
}

databases = {
  appdb = {}
}
