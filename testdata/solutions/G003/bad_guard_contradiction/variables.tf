variable "name" {
  description = "Service name; names the resource group, plan, and app."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 lowercase alphanumeric/hyphen characters."
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

variable "sku_name" {
  description = "App Service plan SKU. Premium v3 tiers support zone redundancy."
  type        = string
  default     = "P1v3"

  validation {
    condition     = contains(["P0v3", "P1v3", "P2v3", "P3v3"], var.sku_name)
    error_message = "sku_name must be a Premium v3 SKU (P0v3-P3v3)."
  }
}

variable "min_instances" {
  description = "Autoscale floor."
  type        = number
  default     = 1

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 2
    error_message = "min_instances must be 1 or 2."
  }
}

variable "max_instances" {
  description = "Autoscale ceiling."
  type        = number
  default     = 6

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires min_instances >= 3."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace that receives the app's logs and metrics; null exports nothing."
  type        = string
  default     = null

  validation {
    condition     = var.log_analytics_workspace_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a Log Analytics workspace resource ID."
  }
}

variable "health_check_path" {
  description = "HTTP path the platform probes; failing instances are removed from rotation."
  type        = string
  default     = "/healthz"
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

variable "tags" {
  description = "Tags merged onto every resource. Optional."
  type        = map(string)
  default     = {}
}
