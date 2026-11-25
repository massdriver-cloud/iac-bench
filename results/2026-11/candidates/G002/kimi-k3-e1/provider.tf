# Credentials come from the environment (application-default credentials,
# workload identity, GOOGLE_APPLICATION_CREDENTIALS, ...).
provider "google" {
  project = var.project_id
  region  = var.region
}
