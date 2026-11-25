variable "kms_key_name" {
  description = "Cloud KMS key that encrypts the instance's data at rest, for example projects/acme-apps/locations/us-central1/keyRings/sql/cryptoKeys/prod. null (the default) means Google-managed encryption. The key must be in var.region and the project's Cloud SQL service account must be able to use it."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[a-z0-9-]+/locations/[a-z0-9-]+/keyRings/[a-zA-Z0-9_-]+/cryptoKeys/[a-zA-Z0-9_-]+$", var.kms_key_name))
    error_message = "kms_key_name must be a full key resource name such as projects/acme-apps/locations/us-central1/keyRings/sql/cryptoKeys/prod."
  }
}
