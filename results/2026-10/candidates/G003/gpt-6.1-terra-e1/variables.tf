variable "name" {
  description = "Globally unique App Service name, also used as the prefix for supporting resources."
  type        = string
  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 40 && can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.name))
    error_message = "name must be 2-40 letters, digits or hyphens, and must start and end with a letter or digit."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to resources."
  type        = map(string)
  default     = {}
}

variable "container_image" {
  description = "Container image name and tag (or digest), without the registry hostname."
  type        = string
  default     = "azure-app-service/samples/aspnethelloworld:latest"
}

variable "container_registry_url" {
  description = "HTTPS URL of the container registry. The default sample image is publicly accessible."
  type        = string
  default     = "https://mcr.microsoft.com"
  validation {
    condition     = startswith(var.container_registry_url, "https://")
    error_message = "container_registry_url must be an HTTPS URL."
  }
}

variable "container_port" {
  description = "Port on which the container accepts HTTP requests."
  type        = number
  default     = 80
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "app_settings" {
  description = "Additional application settings. Platform-managed settings take precedence. Do not put secrets here unless you accept their storage in state; prefer Key Vault references."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "health_check_path" {
  description = "Unauthenticated HTTP health endpoint, beginning with /. It must return 200-299 when healthy."
  type        = string
  default     = "/"
  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must begin with /."
  }
}

variable "sku_name" {
  description = "Linux App Service plan SKU. Use a Premium SKU for the default autoscaling and slots."
  type        = string
  default     = "P1v3"
}

variable "minimum_instances" {
  description = "Minimum and initial instance count. Two or more are recommended for availability."
  type        = number
  default     = 2
  validation {
    condition     = var.minimum_instances >= 1 && floor(var.minimum_instances) == var.minimum_instances
    error_message = "minimum_instances must be a positive integer."
  }
}

variable "maximum_instances" {
  description = "Maximum instance count for CPU autoscaling."
  type        = number
  default     = 4
  validation {
    condition     = var.maximum_instances >= 1 && floor(var.maximum_instances) == var.maximum_instances
    error_message = "maximum_instances must be a positive integer."
  }
}

variable "enable_autoscale" {
  description = "Enable Azure Monitor CPU autoscaling. The selected SKU must support autoscale."
  type        = bool
  default     = true
}

variable "enable_staging_slot" {
  description = "Create a staging slot for deployment and manual swaps; the SKU must support slots."
  type        = bool
  default     = false
}

variable "staging_container_image" {
  description = "Image for the staging slot, or null to use container_image."
  type        = string
  default     = null
  nullable    = true
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "log_retention_days must be an integer between 30 and 730."
  }
}
