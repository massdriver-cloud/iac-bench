variable "bucket_name" {
  description = "Globally unique S3 bucket name within the AWS partition. Use 3–63 lowercase letters, digits, and hyphens, starting and ending with a letter or digit. Dots are deliberately not allowed for virtual-hosted HTTPS compatibility."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "Use 3–63 lowercase letters, digits, or hyphens, start and end with a letter or digit, and avoid S3-reserved prefixes and suffixes."
  }
}

variable "aws_region" {
  description = "AWS region for the bucket. If omitted, use the region from the environment or AWS configuration."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags, such as Application, Environment, or Owner. The module sets Name and ManagedBy."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional ARN of an existing, symmetric customer-managed KMS key in the bucket's region. Without it the bucket defaults to SSE-S3."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws(-[a-z0-9-]+)?:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, not an alias, key ID, or alias ARN."
  }
}

variable "retention" {
  description = "Optional bucket-wide lifecycle limits in whole days. Leave a limit unset to avoid automatic expiration. Current-version expiration hides objects; noncurrent-version expiration permanently deletes older versions."
  type = object({
    current_days    = optional(number)
    noncurrent_days = optional(number)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for days in [var.retention.current_days, var.retention.noncurrent_days] :
      days == null ? true : (days >= 1 && days == floor(days))
    ])
    error_message = "Retention limits must be positive whole numbers of days, or unset."
  }
}

variable "cors_rules" {
  description = "Optional browser CORS rules. Leave empty unless a browser app needs cross-origin access. CORS does not authorize requests."
  type = list(object({
    allowed_origins = set(string)
    allowed_methods = set(string)
    allowed_headers = optional(set(string), [])
    expose_headers  = optional(set(string), [])
    max_age_seconds = optional(number, 300)
  }))
  default  = []
  nullable = false

  validation {
    condition = length(var.cors_rules) <= 100 && alltrue([
      for rule in var.cors_rules : try(
        length(rule.allowed_origins) > 0 && length(rule.allowed_methods) > 0 &&
        alltrue([for method in rule.allowed_methods : contains(["GET", "PUT", "HEAD", "POST", "DELETE"], method)]) &&
        alltrue([for origin in rule.allowed_origins : origin == "*" || can(regex("^https?://[^/[:space:]]+$", origin))]) &&
        rule.max_age_seconds >= 0 && rule.max_age_seconds == floor(rule.max_age_seconds),
        false
      )
    ])
    error_message = "Supply at most 100 CORS rules, each with at least one origin (scheme and host, optional port, no path, or '*'), at least one S3-supported HTTP method, and a nonnegative whole-number max age."
  }
}

variable "access_logging" {
  description = "Optional S3 server access logging to an existing, separately managed destination bucket in the same AWS account and region. If omitted, server access logging is not enabled."
  type = object({
    target_bucket = string
    target_prefix = optional(string)
  })
  default = null

  validation {
    condition     = var.access_logging == null ? true : try(length(trimspace(var.access_logging.target_bucket)) > 0, false)
    error_message = "access_logging.target_bucket must be a nonempty bucket name."
  }
}
