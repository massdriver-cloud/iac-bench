variable "application" {
  description = "Name of the application that owns this bucket (lowercase alphanumeric and hyphens, e.g. \"checkout-api\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,28}[a-z0-9]$", var.application)) && !can(regex("--", var.application))
    error_message = "application must be 2-30 characters, lowercase alphanumeric and single hyphens only, starting and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g. \"dev\", \"staging\", \"prod\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,13}[a-z0-9]$", var.environment)) && !can(regex("--", var.environment))
    error_message = "environment must be 2-15 characters, lowercase alphanumeric and single hyphens only, starting and ending with an alphanumeric character."
  }
}

variable "purpose" {
  description = "Short label describing what this bucket stores (used in naming and tagging, e.g. \"assets\", \"uploads\", \"media\", \"exports\", \"logs\")."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,13}[a-z0-9]$", var.purpose)) && !can(regex("--", var.purpose))
    error_message = "purpose must be 2-15 characters, lowercase alphanumeric and single hyphens only, starting and ending with an alphanumeric character."
  }
}

variable "use_case" {
  description = "Preset profile tuning versioning and lifecycle defaults for common asset types: \"assets\" (general app assets), \"uploads\" (user uploads), \"media\" (images/videos), \"generated\" (app-generated files/exports), or \"logs\" (application/audit logs)."
  type        = string
  default     = "assets"

  validation {
    condition     = contains(["assets", "uploads", "media", "generated", "logs"], var.use_case)
    error_message = "use_case must be one of: assets, uploads, media, generated, logs."
  }
}

variable "bucket_name" {
  description = "Optional explicit globally unique S3 bucket name. If omitted, a unique name prefixed with \"<application>-<environment>-<purpose>-\" is generated automatically."
  type        = string
  default     = null

  validation {
    condition     = var.bucket_name == null || (can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) && !can(regex("\\.\\.", var.bucket_name)) && !can(regex("^xn--", var.bucket_name)) && !can(regex("-s3alias$", var.bucket_name)))
    error_message = "bucket_name must be a valid S3 bucket name (3-63 chars, lowercase alphanumeric, hyphens, or single dots)."
  }
}

variable "force_destroy" {
  description = "Allow Terraform/OpenTofu to delete the bucket even if it still contains objects (including object versions). Keep false for production data."
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Override whether S3 object versioning is enabled. Defaults to true for assets/uploads/media/generated, and false for logs."
  type        = bool
  default     = null
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for SSE-KMS encryption with S3 Bucket Keys enabled. When null, SSE-S3 (AES256) is used."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after which incomplete multipart uploads are automatically aborted."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1 && var.abort_incomplete_multipart_upload_days <= 365 && floor(var.abort_incomplete_multipart_upload_days) == var.abort_incomplete_multipart_upload_days
    error_message = "abort_incomplete_multipart_upload_days must be an integer between 1 and 365."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Override days after which noncurrent object versions are permanently deleted when versioning is enabled. Set to 0 to disable noncurrent version expiration. Defaults to 90 (30 for generated)."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_expiration_days == null || (var.noncurrent_version_expiration_days >= 0 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days)
    error_message = "noncurrent_version_expiration_days must be a non-negative integer."
  }
}

variable "noncurrent_versions_to_retain" {
  description = "Optional minimum number of newer noncurrent versions to retain past noncurrent_version_expiration_days."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_versions_to_retain == null || (var.noncurrent_versions_to_retain >= 1 && var.noncurrent_versions_to_retain <= 100 && floor(var.noncurrent_versions_to_retain) == var.noncurrent_versions_to_retain)
    error_message = "noncurrent_versions_to_retain must be an integer between 1 and 100."
  }
}

variable "object_expiration_days" {
  description = "Override days after which current objects expire automatically. Defaults to null (never expire) except for \"logs\" (365 days). Set to 0 to explicitly disable expiration."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null || (var.object_expiration_days >= 0 && floor(var.object_expiration_days) == var.object_expiration_days)
    error_message = "object_expiration_days must be a non-negative integer."
  }
}

variable "intelligent_tiering_days" {
  description = "Override days after which objects >= 128 KB transition to S3 Intelligent-Tiering. Defaults to 30 for assets/uploads/media, null for others. Set to -1 to disable."
  type        = number
  default     = null

  validation {
    condition     = var.intelligent_tiering_days == null || (var.intelligent_tiering_days >= -1 && floor(var.intelligent_tiering_days) == var.intelligent_tiering_days)
    error_message = "intelligent_tiering_days must be an integer >= -1."
  }
}

variable "cors_allowed_origins" {
  description = "List of browser origins allowed to make CORS requests to this bucket (e.g. [\"https://app.example.com\"]). Leave empty to disable CORS."
  type        = list(string)
  default     = []
}

variable "cors_allowed_methods" {
  description = "HTTP methods allowed for CORS requests when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST"]

  validation {
    condition     = length(var.cors_allowed_methods) > 0 && alltrue([for m in var.cors_allowed_methods : contains(["GET", "HEAD", "PUT", "POST", "DELETE"], m)])
    error_message = "cors_allowed_methods must be non-empty and contain valid S3 CORS methods (GET, HEAD, PUT, POST, DELETE)."
  }
}

variable "read_write_principal_arns" {
  description = "Optional list of IAM principal ARNs (e.g. application role ARNs) granted read/write access in the bucket policy."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.read_write_principal_arns : can(regex("^arn:aws[a-z-]*:(iam|sts)::[0-9]{12}:.+$", arn))])
    error_message = "All entries in read_write_principal_arns must be valid IAM or STS principal ARNs."
  }
}

variable "read_only_principal_arns" {
  description = "Optional list of IAM principal ARNs granted read-only access in the bucket policy."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.read_only_principal_arns : can(regex("^arn:aws[a-z-]*:(iam|sts)::[0-9]{12}:.+$", arn))])
    error_message = "All entries in read_only_principal_arns must be valid IAM or STS principal ARNs."
  }
}

variable "cloudfront_distribution_arns" {
  description = "Optional list of CloudFront distribution ARNs granted read access via Origin Access Control (OAC)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.cloudfront_distribution_arns : can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", arn))])
    error_message = "All entries in cloudfront_distribution_arns must be valid CloudFront distribution ARNs."
  }
}

variable "additional_bucket_policy_documents" {
  description = "Optional list of JSON-encoded IAM policy documents to merge into the bucket policy."
  type        = list(string)
  default     = []
}

variable "access_log_bucket_name" {
  description = "Optional target S3 bucket name for S3 server access logs."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  description = "Optional key prefix for S3 server access logs when access_log_bucket_name is set. Defaults to \"<application>/<environment>/<purpose>/\"."
  type        = string
  default     = null
}

variable "enable_eventbridge" {
  description = "Send S3 object lifecycle notifications (Object Created, Object Deleted, etc.) to Amazon EventBridge."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to the bucket."
  type        = map(string)
  default     = {}
}
