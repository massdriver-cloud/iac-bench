variable "purpose" {
  description = "Short purpose slug for the bucket name (e.g. webapp, downloads)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,24}$", var.purpose))
    error_message = "purpose must be 2-24 lowercase alphanumeric/hyphen characters."
  }
}

variable "environment" {
  description = "Deployment environment; drives access logging and deletion safety."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "transition_days" {
  description = "Days before objects transition to infrequent-access storage. 0 disables the transition entirely."
  type        = number
  default     = 30

  validation {
    condition     = var.transition_days == 0 || var.transition_days >= 30
    error_message = "transition_days must be 0 (disabled) or at least 30 (S3 minimum for STANDARD_IA)."
  }
}

variable "noncurrent_expiration_days" {
  description = "Days before old object versions are deleted. 0 (the default) keeps versions forever — deletion is opt-in."
  type        = number
  default     = 0

  validation {
    condition     = var.noncurrent_expiration_days >= 0
    error_message = "noncurrent_expiration_days must be 0 (disabled) or a positive number of days."
  }
}

variable "extra_tags" {
  description = "Additional tags merged onto every resource. Optional."
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region the bucket lives in."
  type        = string
  default     = "us-east-1"
}
