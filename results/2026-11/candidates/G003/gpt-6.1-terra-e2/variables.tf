variable "name" {
  description = "Globally unique App Service name; also used as the prefix for related resources."
  type        = string
  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 50 && can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-50 alphanumeric characters or hyphens, starting and ending with an alphanumeric character."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create for this service."
  type        = string
}

variable "location" {
  description = "Azure region for the service and observability resources."
  type        = string
}

variable "image" {
  description = "Container image name including tag or digest, without the registry hostname (for example library/nginx:1.27)."
  type        = string
  validation {
    condition     = length(trimspace(var.image)) > 0
    error_message = "image must not be empty."
  }
}

variable "registry_url" {
  description = "HTTPS URL of the container registry. Defaults to Docker Hub."
  type        = string
  default     = "https://index.docker.io"
  validation {
    condition     = startswith(var.registry_url, "https://")
    error_message = "registry_url must use HTTPS."
  }
}

variable "registry_use_managed_identity" {
  description = "Use the app's system-assigned identity to pull from Azure Container Registry. Grant that identity AcrPull on the registry separately."
  type        = bool
  default     = false
}

variable "container_port" {
  description = "HTTP port on which the container listens."
  type        = number
  default     = 8080
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "health_check_path" {
  description = "Unauthenticated HTTP endpoint used by App Service to remove unhealthy instances."
  type        = string
  default     = "/health"
  validation {
    condition     = startswith(var.health_check_path, "/") && !startswith(var.health_check_path, "//")
    error_message = "health_check_path must be an absolute path beginning with /."
  }
}

variable "sku_name" {
  description = "Linux App Service plan SKU. Use a production SKU that supports slots, autoscale and always-on."
  type        = string
  default     = "P1v3"
}

variable "minimum_instances" {
  description = "Minimum and initial number of plan instances."
  type        = number
  default     = 2
  validation {
    condition     = var.minimum_instances >= 2 && floor(var.minimum_instances) == var.minimum_instances
    error_message = "minimum_instances must be an integer of at least 2."
  }
}

variable "maximum_instances" {
  description = "Maximum number of plan instances for autoscaling."
  type        = number
  default     = 5
  validation {
    condition     = var.maximum_instances >= var.minimum_instances && floor(var.maximum_instances) == var.maximum_instances
    error_message = "maximum_instances must be an integer greater than or equal to minimum_instances."
  }
}

variable "zone_balancing_enabled" {
  description = "Spread instances across availability zones; requires a supported region and SKU and at least three instances."
  type        = bool
  default     = false
  validation {
    condition     = !var.zone_balancing_enabled || var.minimum_instances >= 3
    error_message = "Zone balancing requires minimum_instances of at least 3."
  }
}

variable "app_settings" {
  description = "Additional container app settings. Reserved settings for port and Application Insights are managed by this module. Prefer Key Vault references for secrets."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "enable_staging_slot" {
  description = "Create a staging slot on the same plan for validation and manual slot swaps."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "log_retention_days must be an integer from 30 to 730."
  }
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = map(string)
  default     = {}
}
