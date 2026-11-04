variable "bucket_name" {
  description = "Globally unique bucket name, 3-63 lowercase letters, digits or hyphens. Dots are intentionally unsupported for virtual-hosted HTTPS compatibility."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "Use 3-63 lowercase letters, digits or hyphens, starting and ending with a letter or digit, without an AWS-reserved prefix or suffix."
  }
}

variable "tags" {
  description = "Tags applied to the bucket (for example Application, Environment, Owner and CostCenter). Provider default tags also apply."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional existing customer-managed KMS key ARN in the bucket's region. Null uses S3-managed AES256 encryption at no KMS request cost. The key policy and application KMS permissions are managed separately."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[a-z0-9-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a KMS key ARN, not an alias ARN."
  }
}

variable "cors_rules" {
  description = "Optional browser CORS rules. Empty disables cross-origin browser access. CORS is not authorization; callers still need IAM credentials or a presigned URL."
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
      length(rule.allowed_origins) > 0 &&
      alltrue([for origin in rule.allowed_origins : can(regex("^https?://[^/ *]+$", origin))]) &&
      length(rule.allowed_methods) > 0 &&
      alltrue([for method in rule.allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], method)]) &&
      rule.max_age_seconds >= 0 && rule.max_age_seconds <= 86400 && floor(rule.max_age_seconds) == rule.max_age_seconds
    ])
    error_message = "Provide at most 100 CORS rules with explicit http(s) origins (no paths or wildcards), S3 methods GET/HEAD/PUT/POST/DELETE, and an integer max_age_seconds from 0 to 86400."
  }
}
