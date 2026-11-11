variable "bucket_name" {
  description = "Globally unique S3 bucket name. Use lowercase letters, digits and hyphens, for example acme-orders-prod-assets-123456789012."
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|\\.mrap|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "Use 3–63 lowercase letters, digits or hyphens, starting and ending with a letter or digit, without AWS-reserved prefixes or suffixes. Dotted names are intentionally unsupported."
  }
}

variable "tags" {
  description = "Tags applied to the bucket, for example Application, Environment, Owner and CostCenter."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional existing customer-managed symmetric KMS key ARN in the bucket's region. Null uses S3-managed AES-256 encryption with no KMS request charges. Key policy and caller KMS permissions remain your responsibility."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[a-z0-9-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, not an alias, key ID or empty string."
  }
}

variable "cors_rules" {
  description = "Optional browser CORS rules. Empty by default. CORS does not grant S3 access; use application IAM or presigned URLs. Use explicit HTTPS origins in production."
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
    error_message = "Supply at most 100 CORS rules, each with nonempty origins, methods from GET/HEAD/PUT/POST/DELETE, and a nonnegative integer max_age_seconds."
  }
}
