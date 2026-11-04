variable "application_name" {
  description = "Name of the application that owns the bucket. Lowercase letters, digits and hyphens; starts with a letter; 2-20 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.application_name)) && !can(regex("--", var.application_name)) && !can(regex("-$", var.application_name))
    error_message = "application_name must be 2-20 characters, start with a letter, contain only lowercase letters, digits and single hyphens, and not end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment the bucket serves."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "asset_class" {
  description = <<-EOT
    Kind of assets the bucket holds. Drives the lifecycle defaults:
      - user-uploads: files submitted by end users. Kept until deleted; old versions kept 30 days.
      - media:        images and videos. Kept until deleted; infrequently accessed objects move to STANDARD_IA after 30 days; old versions kept 30 days.
      - generated:    derived or regenerable files. Current objects expire after 90 days; old versions kept 7 days.
      - logs:         application logs. Moved to STANDARD_IA after 30 days, expire after 365 days; old versions kept 30 days.
  EOT
  type        = string
  default     = "user-uploads"

  validation {
    condition     = contains(["user-uploads", "media", "generated", "logs"], var.asset_class)
    error_message = "asset_class must be one of: user-uploads, media, generated, logs."
  }
}

variable "object_expiration_days" {
  description = "Optional override: delete current objects after this many days. Leave null to use the asset_class default (logs and generated have defaults; user-uploads and media keep objects until deleted)."
  type        = number
  default     = null

  validation {
    condition     = var.object_expiration_days == null ? true : (var.object_expiration_days >= 1 && var.object_expiration_days <= 36500)
    error_message = "object_expiration_days must be null or between 1 and 36500."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for default encryption. Leave null to use S3-managed encryption (AES256)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-zA-Z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be null or a KMS key ARN."
  }
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to access the bucket directly (for example https://app.example.com). Empty list disables CORS."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : can(regex("^https://", o)) || can(regex("^http://localhost(:[0-9]+)?$", o))])
    error_message = "cors_allowed_origins entries must be https:// origins (http://localhost is allowed for local development)."
  }
}

variable "tags" {
  description = "Additional tags to apply to the bucket. Standard tags (application, environment, asset-class, managed-by) are always applied and take precedence."
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region to create the bucket in."
  type        = string
  default     = "us-east-1"
}
