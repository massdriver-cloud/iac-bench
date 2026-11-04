variable "bucket_name" {
  description = "Globally unique S3 bucket name for the application's assets."
  type        = string

  validation {
    condition     = length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 && can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name)) && !can(regex("\\.\\.", var.bucket_name))
    error_message = "bucket_name must be 3-63 characters, use lowercase letters, numbers, dots or hyphens, and start and end with a letter or number."
  }
}

variable "application_name" {
  description = "Human-readable name of the application that owns this bucket."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.application_name)) > 0
    error_message = "application_name must not be empty."
  }
}

variable "environment" {
  description = "Deployment environment, for example dev, staging, or prod."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.environment)) > 0
    error_message = "environment must not be empty."
  }
}

variable "force_destroy" {
  description = "Allow Terraform to delete a non-empty bucket. Keep false for normal use to prevent accidental data loss."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional resource tags. Standard Name, Application, Environment, and ManagedBy tags are set by this module and take precedence."
  type        = map(string)
  default     = {}
}
