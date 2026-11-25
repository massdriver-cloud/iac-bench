# Application-layer encryption of Kubernetes Secrets. Unless the caller brings
# a key, each cluster gets its own key ring and key in the cluster's region.
#
# Notes for operators:
# - KMS key rings and keys can never be deleted from Google Cloud. Destroying
#   this module schedules the key VERSIONS for destruction (30 days, during
#   which they can be restored) and leaves an empty, free key ring behind.
# - Do not disable or destroy key versions while the cluster exists: the API
#   server would no longer be able to read its Secrets.

resource "google_project_service" "kms" {
  count = local.create_secrets_key ? 1 : 0

  project            = local.project_id
  service            = "cloudkms.googleapis.com"
  disable_on_destroy = false
}

resource "google_kms_key_ring" "gke" {
  count = local.create_secrets_key ? 1 : 0

  project  = local.project_id
  name     = "gke-${var.name}-${random_id.suffix.hex}"
  location = var.region

  depends_on = [google_project_service.kms]
}

resource "google_kms_crypto_key" "secrets" {
  count = local.create_secrets_key ? 1 : 0

  name            = "secrets"
  key_ring        = google_kms_key_ring.gke[0].id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s" # 90 days

  labels = local.labels
}

# Only the GKE service agent of this project may use the key.
resource "google_kms_crypto_key_iam_member" "gke_service_agent" {
  count = local.create_secrets_key ? 1 : 0

  crypto_key_id = google_kms_crypto_key.secrets[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = local.gke_service_agent

  # The service agent only exists once the GKE API is enabled.
  depends_on = [google_project_service.container]
}

# GKE checks that it can use the key when the cluster is created, and IAM
# grants take a little while to become effective everywhere.
resource "time_sleep" "secrets_key_iam_propagation" {
  count = local.create_secrets_key ? 1 : 0

  create_duration = "60s"

  triggers = {
    grant = google_kms_crypto_key_iam_member.gke_service_agent[0].id
  }
}
