variable "service" {
  description = "Service name slug; names the resource group, plan, and app."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.service))
    error_message = "service must be 3-30 lowercase alphanumeric/hyphen characters."
  }
}

variable "environment" {
  description = "Deployment environment; sets the default instance count, zone redundancy, and log retention."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "container_image" {
  description = "Container image and tag to run, e.g. myteam/api:1.4.2."
  type        = string
}

variable "registry_url" {
  description = "Registry the image is pulled from."
  type        = string
  default     = "https://mcr.microsoft.com"
}

variable "size" {
  description = "Capacity tier: small, medium, or large. Maps to a Premium v3 SKU."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.size)
    error_message = "size must be one of: small, medium, large."
  }
}

variable "instance_count" {
  description = "Number of plan instances. Defaults by environment: 3 in prod (spread across zones), 2 in staging, 1 in dev."
  type        = number
  default     = null

  validation {
    condition     = var.instance_count == null ? true : (var.instance_count >= 1 && var.instance_count <= 30 && floor(var.instance_count) == var.instance_count)
    error_message = "instance_count must be a whole number from 1 to 30."
  }
}

variable "health_check_path" {
  description = "HTTP path the platform probes; failing instances are removed from rotation."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}

variable "app_settings" {
  description = "Environment variables for the service. Use Key Vault references for secrets."
  type        = map(string)
  default     = {}
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "extra_tags" {
  description = "Additional tags merged onto every resource. Optional."
  type        = map(string)
  default     = {}
}
