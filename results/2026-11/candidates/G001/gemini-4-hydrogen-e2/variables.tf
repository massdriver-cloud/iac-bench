variable "app_name" {
  description = "Short, lowercase slug identifying the application that owns this bucket (e.g., 'checkout-api')."
  type        = string

  validation {
    condition     = length(var.app_name) >= 2 && length(var.app_name) <= 32 && can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", var.app_name)) && !strcontains(var.app_name, "--")
    error_message = "app_name must be 2-32 characters of lowercase letters, digits, and single hyphens, starting and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g., 'dev', 'staging', 'prod')."
  type        = string

  validation {
    condition     = length(var.environment) >= 2 && length(var.environment) <= 16 && can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", var.environment)) && !strcontains(var.environment, "--")
    error_message = "environment must be 2-16 characters of lowercase letters, digits, and single hyphens, starting and ending with a letter or digit."
  }
}

variable "purpose" {
  description = "Short descriptor for what this bucket stores, used to distinguish multiple buckets owned by the same app (e.g., 'assets', 'uploads', 'media', 'logs')."
  type        = string
  default     = "assets"

  validation {
    condition     = length(var.purpose) >= 2 && length(var.purpose) <= 20 && can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", var.purpose)) && !strcontains(var.purpose, "--")
    error_message = "purpose must be 2-20 characters of lowercase letters, digits, and single hyphens, starting and ending with a letter or digit."
  }
}

variable "asset_profile" {
  description = "Workload profile selecting sensible versioning and lifecycle defaults: 'general', 'uploads', 'media', 'generated', or 'logs'."
  type        = string
  default     = "general"

  validation {
    condition     = contains(["general", "uploads", "media", "generated", "logs"], var.asset_profile)
    error_message = "asset_profile must be one of: general, uploads, media, generated, logs."
  }
}

variable "versioning_enabled" {
  description = "Override object versioning. Defaults to true for all profiles except 'logs' (false)."
  type        = bool
  default     = null
}

variable "expiration_days" {
  description = "Number of days after which current objects expire. Set to 0 to disable expiration. Defaults to null (keep forever for general/uploads/media; 90 days for generated; 365 days for logs)."
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null || (var.expiration_days >= 0 && floor(var.expiration_days) == var.expiration_days)
    error_message = "expiration_days must be null or a non-negative integer."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent object versions expire. Defaults to 30 (general/uploads/media) or 7 (generated/logs)."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_expiration_days == null || (var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be null or a positive integer (>= 1)."
  }
}

variable "intelligent_tiering_enabled" {
  description = "Automatically transition objects >= 128 KB to S3 Intelligent-Tiering for cost optimization."
  type        = bool
  default     = true
}

variable "intelligent_tiering_transition_days" {
  description = "Days before transitioning eligible objects (>= 128 KB) to S3 Intelligent-Tiering. Automatically skipped if expiration_days is shorter."
  type        = number
  default     = 30

  validation {
    condition     = var.intelligent_tiering_transition_days >= 0 && floor(var.intelligent_tiering_transition_days) == var.intelligent_tiering_transition_days
    error_message = "intelligent_tiering_transition_days must be a non-negative integer."
  }
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for SSE-KMS encryption. When null (default), SSE-S3 (AES256) with S3 Bucket Keys is used."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN."
  }
}

variable "cors_allowed_origins" {
  description = "List of browser origins allowed to access this bucket via CORS (e.g., ['https://app.example.com']). Leave empty to disable CORS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : can(regex("^https?://(\\*\\.)?[a-zA-Z0-9.-]+(:[0-9]+)?$", o))])
    error_message = "Each entry in cors_allowed_origins must be an explicit http(s) origin URL (wildcard subdomains like 'https://*.example.com' are allowed, bare '*' is not)."
  }
}

variable "cors_allowed_methods" {
  description = "HTTP methods permitted when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]

  validation {
    condition     = length(var.cors_allowed_methods) > 0 && alltrue([for m in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)])
    error_message = "cors_allowed_methods must contain one or more of: GET, HEAD, PUT, POST, DELETE."
  }
}

variable "cloudfront_distribution_arns" {
  description = "Optional list of CloudFront distribution ARNs granted read-only access (s3:GetObject) via Origin Access Control (OAC)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.cloudfront_distribution_arns : can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:distribution/.+$", a))])
    error_message = "Each entry in cloudfront_distribution_arns must be a valid CloudFront distribution ARN."
  }
}

variable "access_log_bucket_id" {
  description = "Optional S3 bucket ID to receive server access logs for this bucket."
  type        = string
  default     = null

  validation {
    condition     = var.access_log_bucket_id == null || length(trimspace(var.access_log_bucket_id)) >= 3
    error_message = "access_log_bucket_id must be null or a valid S3 bucket name."
  }
}

variable "enable_eventbridge" {
  description = "Emit S3 object events to Amazon EventBridge for asynchronous processing (e.g., thumbnailing, scanning)."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow Terraform/OpenTofu to delete the bucket even if it contains objects. Keep false in production to prevent accidental data loss."
  type        = bool
  default     = false
}

variable "create_iam_policies" {
  description = "Create least-privilege read-only and read-write IAM managed policies scoped to this bucket."
  type        = bool
  default     = true
}

variable "additional_bucket_policy_json" {
  description = "Optional JSON IAM policy document merged into the bucket policy (TLS enforcement always remains active)."
  type        = string
  default     = null

  validation {
    condition     = var.additional_bucket_policy_json == null || can(jsondecode(var.additional_bucket_policy_json))
    error_message = "additional_bucket_policy_json must be null or valid JSON."
  }
}

variable "tags" {
  description = "Additional resource tags merged with standard module tags."
  type        = map(string)
  default     = {}
}
