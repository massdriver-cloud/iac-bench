variable "bucket_name" {
  description = "Globally unique bucket name: 3-63 lowercase letters, digits or hyphens, starting and ending with a letter or digit. Dots are deliberately unsupported for TLS compatibility."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Use 3-63 lowercase letters, digits or hyphens; start and end with a letter or digit."
  }

  validation {
    condition     = !can(regex("^(xn--|sthree-|amzn-s3-demo-)|(-s3alias|--ol-s3|--x-s3|--table-s3)$", var.bucket_name))
    error_message = "The bucket name must not use an S3-reserved prefix or suffix."
  }
}

variable "tags" {
  description = "Tags for ownership, environment and cost allocation."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional existing customer-managed KMS key ARN in the bucket's region. Null uses S3-managed AES-256 encryption with no KMS request charges."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[a-z0-9-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "Provide a KMS key ARN (not an alias), or null for S3-managed encryption."
  }
}

variable "cors_rules" {
  description = "Optional browser CORS rules. Empty disables CORS. CORS never grants S3 permissions; use IAM or presigned URLs."
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
      alltrue([for origin in rule.allowed_origins : length(trimspace(origin)) > 0]) &&
      length(rule.allowed_methods) > 0 &&
      alltrue([for method in rule.allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], method)]) &&
      rule.max_age_seconds >= 0 && rule.max_age_seconds == floor(rule.max_age_seconds)
    ])
    error_message = "Supply at most 100 CORS rules, each with nonempty origins, supported uppercase methods (GET, HEAD, PUT, POST, DELETE), and a nonnegative integer max_age_seconds."
  }
}
