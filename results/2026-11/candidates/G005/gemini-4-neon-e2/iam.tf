# Dedicated least-privilege service account for GKE worker nodes.
# Never uses the overly-permissive Compute Engine default service account.
# Product workloads accessing Pub/Sub, Cloud Storage, and Cloud SQL authenticate
# per-Kubernetes-ServiceAccount via Workload Identity Federation, not via this SA.
resource "google_service_account" "nodes" {
  account_id   = local.node_sa_account_id
  project      = var.project_id
  display_name = "GKE nodes (${var.cluster_name})"
  description  = "Least-privilege node identity for GKE cluster ${var.cluster_name} in ${var.region}. Managed by OpenTofu."
}

# Google's official least-privilege role for GKE node telemetry (Cloud Logging,
# Cloud Monitoring, resource metadata, and cluster autoscaling metrics).
resource "google_project_iam_member" "node_default" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Allow worker nodes to pull container images from Artifact Registry in this
# project and any additional shared CI/CD registry projects.
# Intentionally does NOT grant roles/storage.objectViewer so nodes cannot read
# product teams' Cloud Storage data buckets.
resource "google_project_iam_member" "node_artifact_registry" {
  for_each = local.artifact_reg_projs

  project = each.value
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# If customer-managed etcd secret encryption (CMEK) is configured, grant the GKE
# service agent permission to encrypt/decrypt secrets with the provided KMS key.
resource "google_kms_crypto_key_iam_member" "etcd_cmek" {
  count = var.database_encryption_kms_key_id != null ? 1 : 0

  crypto_key_id = var.database_encryption_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@container-engine-robot.iam.gserviceaccount.com"
}
