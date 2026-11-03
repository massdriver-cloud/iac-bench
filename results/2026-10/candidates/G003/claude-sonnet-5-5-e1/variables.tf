variable "name" {
  description = "Service name. Used as the base for all resource names; the web app hostname is <name>.azurewebsites.net, so it must be globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 chars, lowercase letters, digits and hyphens, not starting or ending with a hyphen."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group the module creates to hold the service's resources (one resource group per service)."
  type        = string
}

variable "location" {
  description = "Azure region. For zone_redundant = true it must support availability zones."
  type        = string
  default     = "eastus2"
}

variable "image" {
  description = "Container image reference, e.g. \"myacr.azurecr.io/orders-api:1.4.2\". Without a registry host, Docker Hub is assumed. Pin a version tag; avoid :latest."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on for HTTP."
  type        = number
  default     = 8080
}

variable "acr_resource_id" {
  description = "Resource ID of the Azure Container Registry hosting the image. When set, the app (and staging slot) pull with their managed identity and are granted AcrPull. When null, the image is pulled anonymously (public registry)."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Non-secret application environment variables. Prefer Key Vault references (@Microsoft.KeyVault(...)) for secrets; the app's managed identity can be granted access out of band."
  type        = map(string)
  default     = {}
}

# ---- Capacity & availability ----

variable "sku_name" {
  description = "App Service plan SKU. Must be a Standard or Premium tier (slots, autoscale); Premium v3 (P*v3) is required for zone redundancy."
  type        = string
  default     = "P1v3"

  validation {
    condition     = can(regex("^(S[1-3]|P[1-3]v[2-3]|P[0-3]mv3)$", var.sku_name))
    error_message = "sku_name must be a Standard (S1-S3) or Premium (P1v2.., P1v3.., P1mv3..) SKU."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires a Premium v3 SKU, a region with availability zones, and min_instances >= 2."
  type        = bool
  default     = true
}

variable "min_instances" {
  description = "Minimum instance count (autoscale floor). Keep >= 2 for production so health-check eviction and zone spreading work."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 30
    error_message = "min_instances must be between 1 and 30."
  }
}

variable "max_instances" {
  description = "Maximum instance count (autoscale ceiling)."
  type        = number
  default     = 6

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "scale_out_cpu_percent" {
  description = "Average CPU % over 5 minutes above which an instance is added."
  type        = number
  default     = 70
}

variable "scale_in_cpu_percent" {
  description = "Average CPU % over 10 minutes below which an instance is removed."
  type        = number
  default     = 30
}

variable "scale_out_memory_percent" {
  description = "Average memory % over 5 minutes above which an instance is added."
  type        = number
  default     = 80
}

# ---- Health & rollout ----

variable "health_check_path" {
  description = "HTTP path probed by App Service; unhealthy instances are removed from rotation and eventually replaced. Must return 2xx when healthy."
  type        = string
  default     = "/healthz"
}

variable "health_check_eviction_minutes" {
  description = "Minutes an instance must keep failing health checks before it is replaced (2-10)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10
    error_message = "health_check_eviction_minutes must be between 2 and 10."
  }
}

variable "enable_staging_slot" {
  description = "Create a 'staging' deployment slot for blue/green rollouts: deploy and warm up there, then swap."
  type        = bool
  default     = true
}

# ---- Observability ----

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace for diagnostics and Application Insights. When null, a dedicated workspace is created."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention in days for the created Log Analytics workspace (ignored if an existing workspace is supplied)."
  type        = number
  default     = 30
}

variable "alert_action_group_ids" {
  description = "Action group IDs notified by the built-in alerts (5xx rate, latency, health). If empty, no alerts are created."
  type        = list(string)
  default     = []
}

variable "alert_http_5xx_threshold" {
  description = "Number of HTTP 5xx responses in 5 minutes that triggers an alert."
  type        = number
  default     = 20
}

variable "alert_response_time_seconds" {
  description = "Average response time (seconds) over 5 minutes that triggers an alert."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
