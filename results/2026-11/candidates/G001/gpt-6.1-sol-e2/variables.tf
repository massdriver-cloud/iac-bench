variable "bucket_name" {
  description = "Globally unique, lowercase S3 bucket name. Treat this as permanent: changing it replaces the bucket."
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "Use 3–63 lowercase letters, digits or hyphens, beginning and ending with a letter or digit; S3 reserved prefixes/suffixes are not allowed. Dots are deliberately unsupported for TLS compatibility."
  }
}

variable "aws_region" {
  description = "AWS region in which to create the bucket. Choose the same region as the application."
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "tags" {
  description = "Tags for ownership, application, environment and cost allocation."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional ARN of a customer-managed KMS key in this region. Null uses S3-managed AES256 encryption (no KMS charges or key permissions required)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, not an alias."
  }
}

variable "force_destroy" {
  description = "DANGER: allow destroy to permanently delete all objects and versions. Leave false for production; true is only for disposable environments."
  type        = bool
  default     = false
  nullable    = false
}

variable "cors_rules" {
  description = "Optional browser CORS rules. Empty disables CORS. Use exact HTTPS application origins; CORS does not grant S3 permissions."
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
      for rule in var.cors_rules :
      length(rule.allowed_origins) > 0 && length(rule.allowed_methods) > 0 &&
      alltrue([for origin in rule.allowed_origins : can(regex("^https://[^/*?#]+(:[0-9]+)?$", origin))]) &&
      alltrue([for method in rule.allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], method)]) &&
      rule.max_age_seconds >= 0 && floor(rule.max_age_seconds) == rule.max_age_seconds
    ])
    error_message = "Provide at most 100 CORS rules, each with exact HTTPS origins (no paths or wildcards), supported uppercase methods, and a nonnegative integer max_age_seconds."
  }
}
