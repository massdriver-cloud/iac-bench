# The clusters live in the same Google Cloud project as the environment VPCs,
# so the provider is wired to the same project/region as the cluster itself.
# Credentials are picked up from the environment (GOOGLE_CREDENTIALS /
# application default credentials / gcloud CLI configuration).
provider "google" {
  project = var.project_id
  region  = var.region
}
