# Dedicated node identity. Nodes never run as the default Compute Engine
# service account, which has the broad Editor role.
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes for ${var.name}"
  description  = "Node identity for the ${var.name} GKE cluster. Workloads authenticate with Workload Identity, not this account."
}

locals {
  # Only what a node needs to run: write logs and metrics, pull images from
  # Artifact Registry. Workloads get their own Google identities through
  # Workload Identity.
  node_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
}

resource "google_project_iam_member" "node_roles" {
  for_each = local.node_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

data "google_project" "this" {
  project_id = var.project_id
}

# Secrets encryption with a customer-managed key. The GKE service agent must be
# able to use the key before the cluster can be created with it.
resource "google_kms_crypto_key_iam_member" "gke_secrets" {
  count = var.secrets_encryption_key == null ? 0 : 1

  crypto_key_id = var.secrets_encryption_key
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this.number}@container-engine-robot.iam.gserviceaccount.com"
}
