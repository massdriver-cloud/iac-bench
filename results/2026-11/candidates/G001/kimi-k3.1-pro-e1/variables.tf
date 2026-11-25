variable "bucket_name" {
  description = "Globally unique S3 bucket name. The module uses this name exactly as supplied."
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name))
    )
    error_message = "bucket_name must be 3-63 characters and contain only lowercase letters, numbers, dots, and hyphens, starting and ending with a letter or number."
  }
}

variable "application" {
  description = "Application name used for the mandatory Application tag."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.application) != ""
    error_message = "application must not be empty."
  }
}

variable "environment" {
  description = "Deployment environment used for the mandatory Environment tag (for example, development or production)."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.environment) != ""
    error_message = "environment must not be empty."
  }
}

variable "tags" {
  description = "Additional resource tags. Name, Application, Environment, and ManagedBy are reserved and set by the module."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "force_destroy" {
  description = "Allow OpenTofu to delete all objects and versions when destroying the bucket. Leave false for recoverability."
  type        = bool
  default     = false
  nullable    = false
}

variable "versioning_enabled" {
  description = "Keep object versions for overwrite and deletion recovery. Setting false suspends versioning but does not remove existing versions."
  type        = bool
  default     = true
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional ARN of a customer-managed KMS key. When null, no-extra-cost SSE-S3 (AES256) encryption is used."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || trimspace(var.kms_key_arn) != ""
    error_message = "kms_key_arn must be null or a non-empty string."
  }
}

variable "incomplete_multipart_upload_days" {
  description = "Days after initiation before incomplete multipart uploads are aborted to avoid hidden storage charges."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = var.incomplete_multipart_upload_days >= 1 && floor(var.incomplete_multipart_upload_days) == var.incomplete_multipart_upload_days
    error_message = "incomplete_multipart_upload_days must be a positive whole number."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to retain noncurrent object versions before permanent deletion."
  type        = number
  default     = 90
  nullable    = false

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days
    error_message = "noncurrent_version_retention_days must be a positive whole number."
  }
}

variable "expiration_rules" {
  description = <<-EOT
    Optional per-prefix expiration rules for disposable data such as logs. Each rule needs a unique id,
    a prefix (use "" for the whole bucket), and a positive number of days. In a versioned bucket,
    expiration creates a noncurrent version; that version is then subject to noncurrent version retention.
  EOT
  type = list(object({
    id     = string
    prefix = string
    days   = number
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for rule in var.expiration_rules :
      trimspace(rule.id) != "" && rule.days >= 1 && floor(rule.days) == rule.days
    ])
    error_message = "Every expiration rule must have a non-empty id and a positive whole number of days."
  }

  validation {
    condition     = length(distinct([for rule in var.expiration_rules : rule.id])) == length(var.expiration_rules)
    error_message = "Expiration rule ids must be unique."
  }

  validation {
    condition = alltrue([
      for rule in var.expiration_rules :
      !contains(["abort-incomplete-multipart-uploads", "expire-noncurrent-versions", "remove-expired-delete-markers"], rule.id)
    ])
    error_message = "Expiration rule ids must not use an id reserved for a built-in lifecycle rule."
  }
}

variable "cors_rules" {
  description = "Optional CORS rules for browser-based uploads or downloads. No cross-origin browser access is allowed by default."
  type = list(object({
    id              = optional(string)
    allowed_headers = optional(list(string), ["*"])
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3000)
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for rule in var.cors_rules :
      length(rule.allowed_methods) > 0 &&
      length(rule.allowed_origins) > 0 &&
      rule.max_age_seconds >= 0 &&
      alltrue([for method in rule.allowed_methods : contains(["GET", "PUT", "HEAD", "POST", "DELETE"], method)])
    ])
    error_message = "Each CORS rule needs at least one origin and method, a non-negative max age, and methods from GET, PUT, HEAD, POST, and DELETE."
  }
}

variable "access_logging" {
  description = <<-EOT
    Optional S3 server access logging destination. target_bucket must be an existing, separate log bucket
    configured to permit delivery from this bucket. target_prefix defaults to s3-access/<bucket-name>/.
  EOT
  type = object({
    target_bucket = string
    target_prefix = optional(string)
  })
  default = null

  validation {
    condition     = var.access_logging == null || trimspace(var.access_logging.target_bucket) != ""
    error_message = "access_logging.target_bucket must not be empty."
  }
}
