locals {
  create_node_service_account = var.node_service_account_email == null
  node_service_account_email  = local.create_node_service_account ? google_service_account.nodes[0].email : var.node_service_account_email
}

# Dedicated, least-privilege identity for the nodes of this cluster.
# Workloads must NOT use this identity — they use Workload Identity
# (Kubernetes service accounts mapped to their own IAM service accounts).
resource "google_service_account" "nodes" {
  count = local.create_node_service_account ? 1 : 0

  project = var.project_id
  # account_id is limited to 30 characters.
  account_id   = trimsuffix(substr("gke-${var.cluster_name}-nodes", 0, 30), "-")
  display_name = "GKE nodes (${var.cluster_name})"
  description  = "Node identity for the ${var.cluster_name} GKE cluster. Managed by OpenTofu."
}

resource "google_project_iam_member" "nodes" {
  for_each = local.create_node_service_account ? toset(var.node_service_account_roles) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes[0].email}"
}

# When application-layer Secrets encryption is enabled, the GKE service
# agent needs access to the caller-provided Cloud KMS key.
data "google_project" "this" {
  count = var.database_encryption_key != null ? 1 : 0

  project_id = var.project_id
}

resource "google_kms_crypto_key_iam_member" "gke_secrets_encryption" {
  count = var.database_encryption_key != null ? 1 : 0

  crypto_key_id = var.database_encryption_key
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this[0].number}@container-engine-robot.iam.gserviceaccount.com"
}
