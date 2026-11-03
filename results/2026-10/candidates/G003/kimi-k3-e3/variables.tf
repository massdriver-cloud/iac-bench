# ---------------------------------------------------------------------------
# Required: what is this service and what does it run?
# ---------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Service name. Used as the web app name (must be globally unique; becomes https://<name>.azurewebsites.net) and as the naming prefix for supporting resources."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,46}[a-z0-9])?$", var.name))
    error_message = "name must be 2-48 characters of lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group the module creates for this service. One resource group per service keeps lifecycle and RBAC boundaries clean."
}

variable "location" {
  type        = string
  description = "Azure region for all resources (e.g. \"westeurope\")."
}

variable "container_image" {
  type        = string
  description = "Container image including tag (e.g. \"myapi:1.4.2\"). Roll out a new version by pointing this at the new tag, applying, and swapping the staging slot into production."
}

variable "container_registry_url" {
  type        = string
  description = "URL of the container registry (e.g. \"https://myregistry.azurecr.io\")."
}

variable "container_port" {
  type        = number
  default     = 8080
  description = "Port the container listens on. Injected into the app via the WEBSITES_PORT app setting."

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

variable "plan_sku" {
  type        = string
  default     = "P1v3"
  description = "App Service plan SKU. The default (P1v3) supports every feature this module uses: deployment slots, autoscale, Always On, health checks and zone redundancy. Free/Shared SKUs are intentionally not supported."

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "P1v2", "P2v2", "P3v2",
      "P0v3", "P1v3", "P2v3", "P3v3",
      "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
      "I1", "I2", "I3",
      "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2",
    ], var.plan_sku)
    error_message = "plan_sku must be a supported Linux App Service plan SKU (Basic, Standard, Premium v2/v3 or Isolated)."
  }
}

variable "plan_instances" {
  type        = number
  default     = 2
  description = "Number of plan workers the service starts on. Run at least 2 for production so a single worker failure or platform upgrade does not take the service down. Must be >= 2 when zone_redundant is true and within [autoscale_min_instances, autoscale_max_instances] when autoscale is enabled."

  validation {
    condition     = var.plan_instances >= 1 && floor(var.plan_instances) == var.plan_instances
    error_message = "plan_instances must be an integer >= 1."
  }
}

variable "autoscale_enabled" {
  type        = bool
  default     = false
  description = "Enable CPU-based autoscale on the plan (scale out above 70% average CPU over 10 minutes, scale in below 25%). Requires a SKU that supports autoscale (Basic or higher)."
}

variable "autoscale_min_instances" {
  type        = number
  default     = 2
  description = "Minimum worker count when autoscale is enabled. Set this to your always-on floor."

  validation {
    condition     = var.autoscale_min_instances >= 1 && floor(var.autoscale_min_instances) == var.autoscale_min_instances
    error_message = "autoscale_min_instances must be an integer >= 1."
  }
}

variable "autoscale_max_instances" {
  type        = number
  default     = 10
  description = "Maximum worker count when autoscale is enabled. This is your cost ceiling."

  validation {
    condition     = var.autoscale_max_instances >= 1 && floor(var.autoscale_max_instances) == var.autoscale_max_instances
    error_message = "autoscale_max_instances must be an integer >= 1."
  }
}

# ---------------------------------------------------------------------------
# Availability
# ---------------------------------------------------------------------------

variable "zone_redundant" {
  type        = bool
  default     = false
  description = "Spread plan workers across availability zones. Requires a Premium v2/v3 SKU and at least 2 plan instances."
}

# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

variable "health_check_path" {
  type        = string
  default     = "/healthz"
  description = "HTTP path App Service polls on every instance. Instances that fail are pulled from the load balancer and replaced after health_check_eviction_time_in_min. Point this at a real readiness endpoint."

  validation {
    condition     = substr(var.health_check_path, 0, 1) == "/"
    error_message = "health_check_path must start with \"/\"."
  }
}

variable "health_check_eviction_time_in_min" {
  type        = number
  default     = 5
  description = "Minutes an instance may fail the health check before App Service replaces it (2-10)."

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "deployment_slot_enabled" {
  type        = bool
  default     = true
  description = "Create a \"staging\" deployment slot. Deploy the new version to the slot, warm it up, then swap it into production for zero-downtime rollouts with instant rollback (swap back). Requires Standard tier or higher."
}

# ---------------------------------------------------------------------------
# Registry access
# ---------------------------------------------------------------------------

variable "acr_id" {
  type        = string
  default     = null
  description = "Resource ID of an Azure Container Registry. When set, the module grants the app's (and staging slot's) system-assigned managed identity AcrPull on the registry and configures the app to pull with that identity - no registry credentials anywhere. Leave null for public/anonymous registries."
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Resource ID of an existing Log Analytics workspace to send diagnostic logs/metrics to and to back Application Insights. When null the module creates a dedicated workspace."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention (days) for the Log Analytics workspace the module creates. Ignored when log_analytics_workspace_id is set."

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

# ---------------------------------------------------------------------------
# Escape hatches
# ---------------------------------------------------------------------------

variable "app_settings" {
  type        = map(string)
  default     = {}
  description = "Extra app settings merged over the module defaults (WEBSITES_PORT, Application Insights wiring). Values here win on conflict."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource the module creates."
}
