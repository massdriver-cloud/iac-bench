# Credentials come from the environment (GOOGLE_CREDENTIALS or application
# default credentials). Project and region are made explicit here so a
# misconfigured shell can never silently place an instance somewhere it
# should not be.
provider "google" {
  project = var.project
  region  = var.region
}
