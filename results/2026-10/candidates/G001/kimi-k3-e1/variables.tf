# =============================================================================
# Required input
#
# This is the only thing an app team MUST supply. Everything else has a
# default chosen by the module.
# =============================================================================

variable "bucket_name" {
  type        = string
  description = <<-EOT
    Name of the bucket. S3 bucket names are globally unique across all of AWS,
    so include your application and environment, e.g. "acme-shop-assets-prod".

    Rules: 3-63 characters; lowercase letters, numbers, dots and hyphens;
    start and end with a letter or number; no adjacent dots; must not be
    formatted like an IP address.
  EOT

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("[.][.]", var.bucket_name)) &&
      !can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.bucket_name))
    )
    error_message = "Invalid bucket_name. Use 3-63 characters of lowercase letters, numbers, dots and hyphens; start and end with a letter or number; no adjacent dots; not formatted like an IP address."
  }
}

# =============================================================================
# Optional inputs — the module's judgment lives in these defaults.
# =============================================================================

variable "versioning_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Keep previous versions of objects when they are overwritten or deleted.
    This is the cheapest "undo" an application can have and protects against
    both bugs and accidents. Old versions are automatically expired after
    noncurrent_version_expiration_days so storage does not grow forever.
    Set to false only for buckets whose contents are trivially regenerable
    (e.g. build artifacts).
  EOT
}

variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 90
  description = "How many days to keep noncurrent (old) object versions before permanently deleting them. Only relevant when versioning_enabled is true."

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  type        = number
  default     = 7
  description = <<-EOT
    Incomplete multipart uploads are invisible to your application but still
    bill you for the parts that were uploaded. The module always aborts and
    cleans them up; this controls after how many days.
  EOT

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1
    error_message = "abort_incomplete_multipart_upload_days must be at least 1."
  }
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = <<-EOT
    ARN of a customer-managed KMS key to encrypt the bucket with. When null
    (the default) the bucket uses SSE-S3 (AES256), which is free, requires no
    key management, and is the right choice for most application assets. Use a
    KMS key when you need key-usage audit trails, cross-account access, or
    regulatory key control.
  EOT

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a full KMS key ARN, e.g. arn:aws:kms:us-east-1:123456789012:key/<id>."
  }
}

variable "allow_public_read" {
  type        = bool
  default     = false
  description = <<-EOT
    DANGEROUS ON PURPOSE TO TURN ON. When true, every object in the bucket is
    readable by anyone on the internet (via a bucket policy granting
    s3:GetObject to *) and the S3 public access block is lifted so that policy
    can take effect. Only enable for genuinely public assets (e.g. marketing
    images served straight from S3). Never enable for user uploads or
    anything customer-specific — use presigned URLs instead.
  EOT
}

variable "cors_allowed_origins" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Origins (e.g. ["https://app.example.com"]) allowed to call this bucket
    from a browser. Leave empty (the default) for no CORS configuration —
    server-side access and presigned-URL flows that POST directly to S3 do
    not need it. Set it when your SPA uploads or reads objects with fetch/XHR.
  EOT
}

variable "cors_allowed_methods" {
  type        = list(string)
  default     = ["GET", "PUT", "POST", "HEAD"]
  description = "HTTP methods allowed by the CORS rule when cors_allowed_origins is set. The default covers browser downloads and uploads."

  validation {
    condition     = alltrue([for m in var.cors_allowed_methods : contains(["GET", "PUT", "POST", "DELETE", "HEAD"], m)])
    error_message = "cors_allowed_methods entries must be one of GET, PUT, POST, DELETE, HEAD."
  }
}

variable "access_log_target_bucket" {
  type        = string
  default     = null
  description = <<-EOT
    Name of an existing bucket that will receive this bucket's server access
    logs. Null (the default) disables access logging. The target bucket must
    permit delivery from the logging service (logging.s3.amazonaws.com) —
    this module does not manage the target bucket.
  EOT
}

variable "access_log_target_prefix" {
  type        = string
  default     = null
  description = "Key prefix for access log objects in the target bucket. Defaults to \"<bucket_name>/\" when access_log_target_bucket is set."
}

variable "additional_bucket_policy_json" {
  type        = string
  default     = null
  description = <<-EOT
    Escape hatch: an additional IAM policy document (as JSON, e.g. the
    output of an aws_iam_policy_document data source) merged into the bucket
    policy. Use it to grant access to other roles, accounts, or AWS services.
    The module's own guardrails (TLS enforcement, and public read only when
    allow_public_read is set) always remain in effect.
  EOT

  validation {
    condition     = var.additional_bucket_policy_json == null || can(jsondecode(var.additional_bucket_policy_json))
    error_message = "additional_bucket_policy_json must be valid JSON."
  }
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = <<-EOT
    When true, destroying the bucket also deletes all objects and versions in
    it. Leave false (the default) so OpenTofu cannot silently destroy a bucket
    that still contains data. Useful for throwaway dev/test buckets only.
  EOT
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the bucket, merged over the module's own defaults ({ ManagedBy = \"OpenTofu\" }). Good things to add: application, environment, team, cost-center."
}
