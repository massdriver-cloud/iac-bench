variable "bucket_name" {
  description = "Globally unique S3 bucket name (3-63 lowercase letters, digits or hyphens; start and end with a letter or digit). Dots and S3-reserved names are intentionally unsupported. Changing this replaces the bucket."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "Use a 3-63 character lowercase, DNS-compatible name without dots or S3-reserved prefixes/suffixes."
  }
}

variable "application" {
  description = "Application name used for ownership and cost-allocation tags."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.application)) > 0 && length(var.application) <= 256
    error_message = "application must be a nonempty name of at most 256 characters."
  }
}

variable "aws_region" {
  description = "AWS region for this standalone root module. Credentials are read from the environment or AWS credential chain."
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "tags" {
  description = "Additional bucket tags. Application and ManagedBy are owned by this module and cannot be overridden."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional ARN of an existing customer-managed symmetric KMS key in the bucket's region. Null uses S3-managed AES256 encryption. The caller owns the key policy and application KMS permissions."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[a-z0-9-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a KMS key ARN, not an alias."
  }
}

variable "cors_rules" {
  description = "Opt-in browser CORS rules. Leave empty for server-only access. CORS never grants S3 authorization; use IAM or presigned URLs."
  type = list(object({
    allowed_origins = list(string)
    allowed_methods = list(string)
    allowed_headers = optional(list(string), [])
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3600)
  }))
  default  = []
  nullable = false

  validation {
    condition = length(var.cors_rules) <= 100 && alltrue([
      for rule in var.cors_rules : (
        length(rule.allowed_origins) > 0 &&
        alltrue([for origin in rule.allowed_origins : length(trimspace(origin)) > 0]) &&
        length(rule.allowed_methods) > 0 &&
        alltrue([for method in rule.allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], method)]) &&
        rule.max_age_seconds >= 0 && floor(rule.max_age_seconds) == rule.max_age_seconds
      )
    ])
    error_message = "Provide at most 100 CORS rules, each with nonempty origins, valid uppercase S3 methods, and a nonnegative integer max_age_seconds."
  }
}
