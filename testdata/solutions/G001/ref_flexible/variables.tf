variable "purpose" {
  description = "Short purpose slug for the bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,24}$", var.purpose))
    error_message = "purpose must be 2-24 lowercase alphanumeric/hyphen characters."
  }
}

variable "environment" {
  description = "Deployment environment; drives versioning, logging, and deletion safety."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "transition_days" {
  description = "Days before objects transition to cheaper storage. 0 disables the transition entirely."
  type        = number
  default     = 30

  validation {
    condition     = var.transition_days >= 0 && floor(var.transition_days) == var.transition_days
    error_message = "transition_days must be 0 (disabled) or a whole number of days."
  }
}

variable "transition_storage_class" {
  description = "Storage class objects transition to."
  type        = string
  default     = "STANDARD_IA"

  validation {
    condition     = contains(["STANDARD_IA", "ONEZONE_IA", "GLACIER_IR"], var.transition_storage_class)
    error_message = "transition_storage_class must be STANDARD_IA, ONEZONE_IA, or GLACIER_IR."
  }
}

variable "noncurrent_expiration_days" {
  description = "Days before old object versions are deleted (prod only; other environments keep no old versions). Defaults to 90 in prod; 0 disables expiry entirely (versions kept forever)."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_expiration_days == null || try(var.noncurrent_expiration_days >= 0 && floor(var.noncurrent_expiration_days) == var.noncurrent_expiration_days, false)
    error_message = "noncurrent_expiration_days must be 0 (disabled) or a whole number of days."
  }
}

variable "force_destroy" {
  description = "Allow destroying the bucket with objects inside. Defaults to the environment's judgment (enabled outside prod); set explicitly to override."
  type        = bool
  default     = null
  nullable    = true
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
