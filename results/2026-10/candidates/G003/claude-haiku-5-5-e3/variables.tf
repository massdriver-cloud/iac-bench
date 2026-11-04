variable "name" {
  description = "Base name for the app. Used for the web app, service plan, slot, and monitoring resources. Lowercase letters, digits and hyphens, 2-40 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "name must be 2-40 chars, start with a letter, end with a letter or digit, and contain only lowercase letters, digits and hyphens."
  }
}

variable "location" {
  description = "Azure region for all resources (for example \"westeurope\")."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group this module creates and deploys into."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Container workload
# ---------------------------------------------------------------------------

variable "container_image" {
  description = "Image reference including tag, without registry host (for example \"payments-api:1.4.2\"). Use the registry URL variable for the host."
  type        = string

  validation {
    condition     = can(regex(":[^:/]+$", var.container_image)) && !startswith(var.container_image, "http")
    error_message = "container_image must include a tag (name:tag) and must not contain a scheme."
  }
}

variable "container_registry_url" {
  description = "Registry base URL including scheme, for example \"https://myacr.azurecr.io\". Null means Docker Hub."
  type        = string
  default     = null

  validation {
    condition     = var.container_registry_url == null || can(regex("^https://", var.container_registry_url))
    error_message = "container_registry_url must start with https://."
  }
}

variable "container_registry_id" {
  description = "Resource ID of an Azure Container Registry. When set, the module grants AcrPull to the web app and staging slot identities and pulls with managed identity (no stored registry credentials)."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on. Exposed to the platform as WEBSITES_PORT."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "health_check_path" {
  description = "HTTP path the platform polls to determine instance health. Must return 200 when the instance is ready to serve."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may stay unhealthy before the platform replaces it. Range 2-10."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

variable "app_settings" {
  description = "Additional application settings. Module-managed settings (WEBSITES_PORT, Application Insights connection) take precedence. Use Key Vault references for secrets."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Capacity and availability
# ---------------------------------------------------------------------------

variable "service_plan_sku" {
  description = "App Service plan SKU. Default is Premium v3, which is required for zone redundancy. B-series is for non-production only."
  type        = string
  default     = "P1v3"

  validation {
    condition     = contains(["B1", "B2", "B3", "S1", "S2", "S3", "P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3"], var.service_plan_sku)
    error_message = "service_plan_sku must be one of B1, B2, B3, S1, S2, S3, P0v3, P1v3, P2v3, P3v3, P1mv3, P2mv3, P3mv3."
  }
}

variable "instance_count" {
  description = "Number of instances when autoscale is disabled. Ignored for the plan's worker count when autoscale_enabled is true."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 30
    error_message = "instance_count must be between 1 and 30."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires a Premium v3 SKU and at least 2 instances (see preconditions)."
  type        = bool
  default     = true
}

variable "autoscale_enabled" {
  description = "Enable CPU-based autoscaling of the service plan between autoscale_min and autoscale_max."
  type        = bool
  default     = false
}

variable "autoscale_min" {
  description = "Minimum instances when autoscale is enabled. Must be at least 2 when zone_redundant is true."
  type        = number
  default     = 2

  validation {
    condition     = var.autoscale_min >= 1 && var.autoscale_min <= 30
    error_message = "autoscale_min must be between 1 and 30."
  }
}

variable "autoscale_max" {
  description = "Maximum instances when autoscale is enabled."
  type        = number
  default     = 6

  validation {
    condition     = var.autoscale_max >= 1 && var.autoscale_max <= 30
    error_message = "autoscale_max must be between 1 and 30."
  }
}

variable "autoscale_scale_out_cpu_percent" {
  description = "Average plan CPU percentage above which to add an instance."
  type        = number
  default     = 70

  validation {
    condition     = var.autoscale_scale_out_cpu_percent > 0 && var.autoscale_scale_out_cpu_percent <= 100
    error_message = "autoscale_scale_out_cpu_percent must be in (0, 100]."
  }
}

variable "autoscale_scale_in_cpu_percent" {
  description = "Average plan CPU percentage below which to remove an instance. Must be lower than the scale-out threshold."
  type        = number
  default     = 30

  validation {
    condition     = var.autoscale_scale_in_cpu_percent >= 0 && var.autoscale_scale_in_cpu_percent < 100
    error_message = "autoscale_scale_in_cpu_percent must be in [0, 100)."
  }
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "staging_slot_enabled" {
  description = "Create a 'staging' deployment slot with the same identity and settings. Deploy to staging, then swap."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Retention in days for the Log Analytics workspace created by this module."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "action_group_ids" {
  description = "Action group IDs notified by the module's alerts."
  type        = list(string)
  default     = []
}

variable "http_5xx_alert_threshold" {
  description = "Number of HTTP 5xx responses in a 5-minute window that triggers the alert."
  type        = number
  default     = 10

  validation {
    condition     = var.http_5xx_alert_threshold >= 1
    error_message = "http_5xx_alert_threshold must be at least 1."
  }
}
