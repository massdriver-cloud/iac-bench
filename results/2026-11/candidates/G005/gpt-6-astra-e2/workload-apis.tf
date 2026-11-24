# Supports both direct Workload Identity Federation and Kubernetes-to-Google
# service-account impersonation. Workload-specific APIs/IAM belong to the apps.
resource "google_project_service" "workload_identity" {
  for_each = toset([
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
