# The instances live in the same Google Cloud project as the environment VPC
# networks, and the Google provider is configured for exactly that project.
# The module makes the project explicit and pins the provider to it so that
# every resource - including ones that have no project argument of their own,
# like google_sql_database_instance - deterministically lands in that project.

provider "google" {
  project = var.project
}
