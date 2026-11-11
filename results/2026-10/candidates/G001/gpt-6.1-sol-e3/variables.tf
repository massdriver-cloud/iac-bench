variable "bucket_name" {
  description = "Globally unique S3 bucket name. Use lowercase letters, digits and hyphens (3-63 characters), starting and ending with a letter or digit."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "Use a valid 3-63 character lowercase, hyphenated S3 name, without AWS-reserved prefixes or suffixes. Dots are intentionally unsupported for HTTPS compatibility."
  }
}

variable "aws_region" {
  description = "AWS region in which to create the bucket. Credentials are obtained from the environment/provider credential chain."
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "tags" {
  description = "Tags applied to the bucket, for example Application, Environment and Owner."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional existing customer-managed KMS key ARN in the same region. Null uses SSE-S3 (AES256). Callers must have KMS permissions and the key policy must allow S3 use."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, not an alias, or null."
  }
}

variable "force_destroy" {
  description = "DANGER: allow OpenTofu to delete all objects and versions when destroying the bucket. Leave false for application data."
  type        = bool
  default     = false
  nullable    = false
}

variable "object_expiration_days" {
  description = "Optional retention period for current objects. Null never expires current objects. Expiration creates delete markers in this versioned bucket; noncurrent versions have separate retention."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null ? true : (var.object_expiration_days >= 1 && floor(var.object_expiration_days) == var.object_expiration_days)
    error_message = "object_expiration_days must be a positive whole number or null."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Optional days after a version becomes noncurrent before permanent deletion. Null preserves old versions indefinitely. This is irreversible data deletion when enabled."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_expiration_days == null ? true : (var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be a positive whole number or null."
  }
}

variable "cors_rules" {
  description = "Optional browser CORS rules; empty disables CORS. CORS does not grant S3 permissions. Prefer exact HTTPS origins and only the methods your app needs."
  type = list(object({
    allowed_origins = set(string)
    allowed_methods = set(string)
    allowed_headers = optional(set(string), [])
    expose_headers  = optional(set(string), [])
    max_age_seconds = optional(number, 3600)
  }))
  default  = []
  nullable = false

  validation {
    condition = length(var.cors_rules) <= 100 && alltrue([
      for rule in var.cors_rules : length(rule.allowed_origins) > 0 &&
      alltrue([for origin in rule.allowed_origins : length(trimspace(origin)) > 0]) &&
      length(rule.allowed_methods) > 0 &&
      alltrue([for method in rule.allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], method)]) &&
      rule.max_age_seconds >= 0 && floor(rule.max_age_seconds) == rule.max_age_seconds
    ])
    error_message = "CORS supports up to 100 rules with nonempty origins, S3 methods (GET, HEAD, PUT, POST, DELETE), and a nonnegative whole-number max age."
  }
}

variable "access_logging" {
  description = "Optional existing S3 server access log destination in the same region/account. Its policy must allow logging.s3.amazonaws.com to write this bucket's logs. Do not use this bucket itself."
  type = object({
    target_bucket = string
    target_prefix = optional(string, "s3-access/")
  })
  default = null

  validation {
    condition     = var.access_logging == null ? true : length(trimspace(var.access_logging.target_bucket)) > 0
    error_message = "The access logging target bucket must not be empty."
  }
}
