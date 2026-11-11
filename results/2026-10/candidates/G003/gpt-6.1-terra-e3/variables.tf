variable "name" {
  description = "Globally unique App Service name. Related resource names are derived from this."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,57}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-59 letters, digits or hyphens, beginning and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  description = "Existing resource group in which to deploy."
  type        = string
}

variable "location" {
  description = "Azure region for the service and its supporting resources."
  type        = string
}

variable "container_image" {
  description = "Container image including tag, excluding registry URL (for example, nginx:stable)."
  type        = string
  validation {
    condition     = length(trimspace(var.container_image)) > 0
    error_message = "container_image must not be empty."
  }
}

variable "container_registry_url" {
  description = "HTTPS registry endpoint. Defaults to Docker Hub."
  type        = string
  default     = "https://index.docker.io"
  validation {
    condition     = startswith(var.container_registry_url, "https://")
    error_message = "container_registry_url must start with https://."
  }
}

variable "acr_resource_id" {
  description = "Optional Azure Container Registry resource ID. Grants AcrPull to each app identity and uses managed identity for pulls."
  type        = string
  default     = null
}

variable "registry_username" {
  description = "Optional registry username for password-based image pulls; do not combine with acr_resource_id."
  type        = string
  default     = null
}

variable "registry_password" {
  description = "Optional registry password. Stored in OpenTofu state."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_port" {
  description = "Port on which the container listens."
  type        = number
  default     = 80
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer from 1 to 65535."
  }
}

variable "health_check_path" {
  description = "Unauthenticated path returning HTTP 200-299 when the service is healthy."
  type        = string
  default     = "/"
  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must begin with /."
  }
}

variable "sku_name" {
  description = "Linux App Service plan SKU; use a SKU supporting slots, health checks and autoscale."
  type        = string
  default     = "P1v3"
}

variable "min_instances" {
  description = "Minimum and initial plan instance count."
  type        = number
  default     = 1
  validation {
    condition     = var.min_instances >= 1 && floor(var.min_instances) == var.min_instances
    error_message = "min_instances must be a positive integer."
  }
}

variable "max_instances" {
  description = "Maximum instance count for CPU autoscaling."
  type        = number
  default     = 3
  validation {
    condition     = var.max_instances >= 1 && floor(var.max_instances) == var.max_instances
    error_message = "max_instances must be a positive integer."
  }
}

variable "zone_balancing_enabled" {
  description = "Distribute plan workers across availability zones. Requires a supported region and SKU and at least three instances."
  type        = bool
  default     = false
}

variable "staging_slot_enabled" {
  description = "Create a staging deployment slot. Swap it to production using Azure deployment tooling after verification."
  type        = bool
  default     = true
}

variable "staging_container_image" {
  description = "Optional image for staging; defaults to the production image. Promote with a slot swap, then update container_image to match."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Additional application settings, shared by production and staging. Values are stored in state. Platform-managed settings override conflicting keys."
  type        = map(string)
  default     = {}
  sensitive   = true
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

variable "tags" {
  description = "Tags applied to resources that support them."
  type        = map(string)
  default     = {}
}
