variable "app_name" {
  description = "Short, lowercase name of the application owning this bucket (e.g., \"checkout-api\", \"media-portal\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$", var.app_name)) && !can(regex("--", var.app_name))
    error_message = "app_name must be 2-32 characters of lowercase letters, numbers, and single hyphens, starting and ending with a letter or number."
  }
}

variable "environment" {
  description = "Deployment environment for the application (e.g., \"dev\", \"staging\", \"prod\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,14}[a-z0-9]$|^[a-z0-9]$", var.environment)) && !can(regex("--", var.environment))
    error_message = "environment must be 1-16 characters of lowercase letters, numbers, and single hyphens, starting and ending with a letter or number."
  }
}

variable "purpose" {
  description = "Short descriptor for what this bucket holds within the application (e.g., \"assets\", \"uploads\", \"videos\", \"logs\"). Used in the bucket name and tags."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,18}[a-z0-9]$|^[a-z0-9]$", var.purpose)) && !can(regex("--", var.purpose))
    error_message = "purpose must be 1-20 characters of lowercase letters, numbers, and single hyphens, starting and ending with a letter or number."
  }
}

variable "usage_profile" {
  description = <<-EOT
    Opinionated lifecycle & versioning preset tuned for common application asset workloads:
    - "uploads":   User uploads & attachments (versioned, 90d noncurrent cleanup, Intelligent-Tiering after 30d).
    - "media":     Images & videos (versioned, 30d noncurrent cleanup, fast 3d multipart abort, Intelligent-Tiering after 30d).
    - "generated": App-generated files/exports (versioned, 14d noncurrent cleanup, Standard-IA after 30d).
    - "logs":      Application logs/archives (versioning suspended, Standard-IA at 30d, Glacier Instant Retrieval at 90d, 365d retention by default).
  EOT
  type        = string
  default     = "uploads"

  validation {
    condition     = contains(["uploads", "media", "generated", "logs"], var.usage_profile)
    error_message = "usage_profile must be one of: \"uploads\", \"media\", \"generated\", \"logs\"."
  }
}

variable "bucket_name_override" {
  description = "Optional explicit S3 bucket name to use instead of the module's deterministic naming convention. Must be globally unique and contain no dots."
  type        = string
  default     = null

  validation {
    condition = var.bucket_name_override == null ? true : (
      length(var.bucket_name_override) >= 3 &&
      length(var.bucket_name_override) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_override)) &&
      !can(regex("--", var.bucket_name_override))
    )
    error_message = "bucket_name_override must be 3-63 characters, lowercase alphanumeric and single hyphens only (no dots), starting and ending with a letter or number."
  }
}

variable "versioning_enabled" {
  description = "Override the usage_profile default for object versioning. When null, versioning is enabled for uploads/media/generated and suspended for logs."
  type        = bool
  default     = null
}

variable "expiration_days" {
  description = "Optional number of days after which current objects automatically expire. Defaults to 365 for the \"logs\" usage_profile and null (never expire) for other profiles. Set to 0 to disable automatic expiration on \"logs\"."
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null ? true : (var.expiration_days >= 0 && floor(var.expiration_days) == var.expiration_days)
    error_message = "expiration_days must be null or a non-negative whole number."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Optional override for how many days noncurrent object versions are kept before expiration (when versioning is enabled). Defaults to the usage_profile preset."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_retention_days == null ? true : (var.noncurrent_version_retention_days >= 1 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days)
    error_message = "noncurrent_version_retention_days must be null or a positive whole number."
  }
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for SSE-KMS encryption (with S3 Bucket Key enabled). When null, SSE-S3 (AES256) is used automatically."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key or alias ARN."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed browser origins (e.g., [\"https://app.example.com\"]) to enable CORS for direct browser uploads/downloads. Leave empty to disable CORS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for origin in var.cors_allowed_origins : can(regex("^https?://[^\\s]+$", origin))])
    error_message = "Each entry in cors_allowed_origins must be an explicit http:// or https:// origin (wildcards like \"*\" are not permitted)."
  }
}

variable "cors_allowed_methods" {
  description = "HTTP methods permitted by CORS when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]

  validation {
    condition     = length(var.cors_allowed_methods) > 0 && alltrue([for m in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)])
    error_message = "cors_allowed_methods must contain valid S3 CORS HTTP methods: GET, HEAD, PUT, POST, DELETE."
  }
}

variable "cloudfront_distribution_arns" {
  description = "Optional list of CloudFront distribution ARNs granted read access (s3:GetObject) via Origin Access Control (OAC)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.cloudfront_distribution_arns : can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", arn))])
    error_message = "Each entry in cloudfront_distribution_arns must be a valid CloudFront distribution ARN."
  }
}

variable "access_logging_bucket" {
  description = "Optional target S3 bucket name for S3 server access logs. Logs are written under the prefix \"<bucket-name>/\"."
  type        = string
  default     = null
}

variable "enable_eventbridge" {
  description = "Set to true to emit S3 object events to Amazon EventBridge for downstream async processing (thumbnails, virus scanning, pipelines)."
  type        = bool
  default     = false
}

variable "create_iam_policies" {
  description = "Set to true to create managed IAM policies (read-only, write-only, read-write) in AWS alongside the JSON policy outputs."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow destroying a non-empty bucket on `tofu destroy`. Keep false outside ephemeral dev/test environments to protect application data."
  type        = bool
  default     = false
}

variable "additional_bucket_policy_json" {
  description = "Optional JSON-encoded IAM policy document whose statements will be merged into the bucket policy (TLS enforcement always remains active)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional resource tags to merge with the module's standard governance tags."
  type        = map(string)
  default     = {}
}
