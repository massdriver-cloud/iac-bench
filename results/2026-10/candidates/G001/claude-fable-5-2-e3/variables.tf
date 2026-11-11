###############################################################################
# Required: the two things only the app team knows
###############################################################################

variable "application" {
  description = "Name of the application that owns this bucket, e.g. \"photo-service\". Lowercase letters, digits and single hyphens."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.application)) &&
      length(var.application) >= 2 && length(var.application) <= 24 &&
      !startswith(var.application, "sthree-") &&
      !startswith(var.application, "amzn-s3-demo-")
    )
    error_message = "application must be 2-24 characters: lowercase letters, digits and single hyphens, starting with a letter (e.g. \"photo-service\")."
  }
}

variable "environment" {
  description = "Deployment environment this bucket belongs to, e.g. \"dev\", \"staging\", \"prod\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.environment))
    error_message = "environment must be 2-8 lowercase letters/digits, starting with a letter (e.g. \"dev\", \"staging\", \"prod\")."
  }
}

###############################################################################
# Optional: everything below has a default chosen by the module
###############################################################################

variable "purpose" {
  description = "What the bucket holds, used in its name. Change it when one application needs more than one bucket, e.g. \"uploads\", \"exports\", \"logs\"."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.purpose)) && length(var.purpose) >= 2 && length(var.purpose) <= 12
    error_message = "purpose must be 2-12 characters: lowercase letters, digits and single hyphens, starting with a letter (e.g. \"uploads\")."
  }
}

variable "tags" {
  description = "Extra tags to put on every resource. The module always adds Application, Environment, Purpose and ManagedBy itself."
  type        = map(string)
  default     = {}
}

variable "cors_allowed_origins" {
  description = "Web origins whose browser code may upload to / download from the bucket directly using presigned URLs, e.g. [\"https://app.example.com\"]. Leave empty if only your backend talks to the bucket."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for o in var.cors_allowed_origins :
      can(regex("^https://[A-Za-z0-9.*-]+(:[0-9]+)?$", o)) || can(regex("^http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?$", o))
    ])
    error_message = "Each origin must look like \"https://app.example.com\" (no path, no trailing slash). Plain http is only allowed for localhost, and a bare \"*\" is not allowed."
  }
}

variable "cloudfront_distribution_arns" {
  description = "ARNs of CloudFront distributions allowed to read objects (via Origin Access Control). This is the supported way to serve images/videos to end users; the bucket itself is never public."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for a in var.cloudfront_distribution_arns :
      can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", a))
    ])
    error_message = "Each entry must be a CloudFront distribution ARN, e.g. \"arn:aws:cloudfront::123456789012:distribution/E2ABCDEFGHIJKL\"."
  }
}

variable "expire_after_days" {
  description = "Automatically delete objects under a key prefix after N days, e.g. { \"tmp/\" = 7, \"logs/\" = 90 }. Use the prefix \"\" to apply to the whole bucket. By default nothing your application wrote is ever deleted."
  type        = map(number)
  default     = {}

  validation {
    condition = alltrue([
      for prefix, days in var.expire_after_days :
      !startswith(prefix, "/") && days >= 1 && floor(days) == days
    ])
    error_message = "Prefixes must not start with \"/\" (S3 keys have no leading slash) and days must be whole numbers >= 1."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How long an overwritten or deleted object can still be recovered. Versioning is always on; old versions are removed after this many days so they do not accumulate cost forever."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days
    error_message = "noncurrent_version_retention_days must be a whole number >= 1."
  }
}

variable "intelligent_tiering_after_days" {
  description = "Move objects to the S3 Intelligent-Tiering storage class after this many days so rarely-read data gets cheaper automatically (no retrieval fees, no latency change). Set to null to keep everything in S3 Standard."
  type        = number
  default     = 30
  nullable    = true

  validation {
    condition     = var.intelligent_tiering_after_days == null ? true : (var.intelligent_tiering_after_days >= 0 && floor(var.intelligent_tiering_after_days) == var.intelligent_tiering_after_days)
    error_message = "intelligent_tiering_after_days must be null or a whole number >= 0."
  }
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to encrypt objects with. Leave null (recommended) and the module creates and manages a dedicated key for this bucket. Must be a value known at plan time."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a full KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias or a bare key id."
  }
}

variable "access_log_bucket_name" {
  description = "Name of an existing central S3 bucket (same region) that receives server access logs. Leave null and the module creates a private companion \"<bucket>-logs\" bucket. The owner of a central bucket must allow S3 log delivery from this account. Must be a value known at plan time."
  type        = string
  default     = null

  validation {
    condition     = var.access_log_bucket_name == null ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket_name))
    error_message = "access_log_bucket_name must be a valid S3 bucket name (not an ARN)."
  }
}

variable "access_log_retention_days" {
  description = "How long access logs are kept in the companion log bucket the module creates. Ignored when access_log_bucket_name is set."
  type        = number
  default     = 90

  validation {
    condition     = var.access_log_retention_days >= 1 && floor(var.access_log_retention_days) == var.access_log_retention_days
    error_message = "access_log_retention_days must be a whole number >= 1."
  }
}

variable "create_iam_policies" {
  description = "Create ready-to-attach IAM managed policies (read-only and read-write) for this bucket. Turn off only if your pipeline may not create IAM policies; the policy JSON is still available as an output."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow `tofu destroy` to delete the bucket even though it still contains objects. Leave false for anything holding real data; useful for short-lived test environments."
  type        = bool
  default     = false
}
