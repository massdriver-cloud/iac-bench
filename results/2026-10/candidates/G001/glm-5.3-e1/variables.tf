###############################################################################
#
# Inputs.
#
# `name` is the only required input. Everything else has a default that is the
# right answer for the overwhelming majority of application asset buckets, and
# exists only for the cases where a team genuinely needs something else.
#
###############################################################################

variable "name" {
  description = <<-EOT
    Base name for the bucket, in the form "<app>-<purpose>", for example
    "checkout-uploads" or "media-processor-outputs".

    The real bucket name is "<name>-<account-id>-<region>" (for example
    "checkout-uploads-123456789012-us-west-2"). S3 bucket names are shared by
    every AWS account on the planet, so the suffix keeps two teams -- or the
    same team's stack in two regions -- from ever fighting over a name. Use the
    `bucket_name` output, not this input, when configuring your application.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,33}[a-z0-9]$", var.name))
    error_message = "name must be 3-35 characters long, use only lowercase letters, digits and hyphens, and start and end with a letter or digit."
  }

  validation {
    condition     = !startswith(var.name, "xn--") && !startswith(var.name, "sthree-")
    error_message = "S3 reserves bucket names beginning with \"xn--\" and \"sthree-\"; please pick a different name."
  }
}

variable "tags" {
  description = "Extra tags to attach to the bucket, e.g. { team = \"checkout\", service = \"payments\" }. Merged on top of the module's own Name tag."
  type        = map(string)
  default     = {}
}

variable "force_destroy" {
  description = <<-EOT
    Allow the bucket to be deleted even while it still contains objects.
    Leave false (the default) in anything resembling production: it is the
    difference between a refused destroy and a bucket of user uploads that is
    gone forever.
  EOT
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Keep every version of every object. This is the undo button for accidental overwrites and deletes; old versions are cleaned up after noncurrent_version_expiration_days so it does not grow forever."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "How long a superseded or deleted object version is kept before it is removed. Only relevant when versioning_enabled is true."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "expiration_days" {
  description = <<-EOT
    Optional. Delete objects this many days after they are uploaded. Leave null
    (the default) to keep objects indefinitely -- the right choice for durable
    app assets. Set it only for genuinely transient data such as scratch space
    or short-lived exports. With versioning on, the object becomes a noncurrent
    version at expiry and is then covered by noncurrent_version_expiration_days.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null || var.expiration_days >= 1
    error_message = "expiration_days must be at least 1 when set."
  }
}

variable "infrequent_access_transition_days" {
  description = <<-EOT
    Optional. Move objects to Standard-Infrequent-Access this many days after
    upload. Use it for assets that are written once and rarely read again
    (archived video, old logs). Objects must stay at least 30 days, because
    Standard-IA bills a 30-day minimum per object.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.infrequent_access_transition_days == null || var.infrequent_access_transition_days >= 30
    error_message = "infrequent_access_transition_days must be at least 30: Standard-IA bills a 30-day minimum per object, so transitioning earlier only adds cost."
  }
}

variable "kms_key_arn" {
  description = <<-EOT
    Optional KMS key used to encrypt objects at rest, as a full key ARN.
    Default: AWS-managed server-side encryption (SSE-S3, AES256), which is
    encrypted at rest with no extra setup, no extra cost and no KMS permissions
    for your app or its IAM roles. Provide a customer-managed key only when you
    have a concrete requirement to control the key (e.g. cross-account key
    policies or cryptographic audit).
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || startswith(var.kms_key_arn, "arn:")
    error_message = "kms_key_arn must be the full ARN of a KMS key (\"arn:...\"), not a bare key id or alias."
  }
}

variable "cors_allowed_origins" {
  description = <<-EOT
    Browser origins allowed to talk to this bucket, for example
    ["https://app.example.com"]. Leave empty unless browsers hit the bucket
    directly (JavaScript uploads, presigned URLs, <img> and <video> tags). A
    CORS rule allowing exactly these origins to GET/HEAD/PUT/POST is attached;
    servers and AWS CLI are unaffected by CORS either way.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for origin in var.cors_allowed_origins :
      origin == "*" || startswith(origin, "https://") || startswith(origin, "http://")
    ])
    error_message = "Each entry in cors_allowed_origins must be a full origin such as \"https://app.example.com\" (or \"*\")."
  }
}

variable "access_logs_bucket" {
  description = "Optional name of an existing bucket that should receive S3 server access logs for this bucket. That bucket must already exist and permit S3 log delivery; this module does not create it."
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "Optional prefix under which access logs are written in access_logs_bucket. Defaults to \"s3-access-logs/<bucket-name>/\"."
  type        = string
  default     = null
}
