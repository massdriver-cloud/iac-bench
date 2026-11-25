variable "app_name" {
  description = "Short, lowercase application name used to form the bucket name and tags."
  type        = string

  validation {
    condition     = length(var.app_name) <= 30 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.app_name))
    error_message = "app_name must be 1-30 lowercase letters, digits, or hyphens, and must start and end with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment, such as dev, staging, or prod."
  type        = string

  validation {
    condition     = length(var.environment) <= 12 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.environment))
    error_message = "environment must be 1-12 lowercase letters, digits, or hyphens, and must start and end with a letter or digit."
  }
}
