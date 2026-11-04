variable "name" {
  type        = string
  description = "Name of the service. Used as the web app name (globally unique within azurewebsites.net) and as the prefix for related resources."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}[a-z0-9]$", var.name))
    error_message = "name must be 3-42 chars, lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "location" {
  type        = string
  description = "Azure region, e.g. \"eastus2\"."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group the module creates to hold all resources."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all taggable resources."
  default     = {}
}

# ----------------------------------------------------------------------------
# Container image
# ----------------------------------------------------------------------------

variable "container_image_name" {
  type        = string
  description = "Image repository path WITHOUT the registry host, e.g. \"acme/orders-api\". Put the host in container_registry_url (omit it for Docker Hub)."

  validation {
    condition     = !can(regex("^[a-z0-9.-]+\\.[a-z]{2,}/", var.container_image_name)) && !can(regex(":", var.container_image_name))
    error_message = "container_image_name must be a repository path without a registry host or tag, e.g. \"acme/orders-api\"."
  }
}

variable "container_image_tag" {
  type        = string
  description = "Image tag to deploy. Immutable tags (e.g. a git SHA) are strongly recommended; \"latest\" is rejected."

  validation {
    condition     = var.container_image_tag != "latest" && length(var.container_image_tag) > 0
    error_message = "container_image_tag must be set to a specific, non-\"latest\" tag."
  }
}

variable "container_registry_url" {
  type        = string
  description = "Registry URL including scheme, e.g. \"https://ghcr.io\". Null means Docker Hub."
  default     = null

  validation {
    condition     = var.container_registry_url == null || can(regex("^https://", var.container_registry_url))
    error_message = "container_registry_url must include the https:// scheme."
  }
}

variable "container_registry_username" {
  type        = string
  description = "Username for a private registry. Leave null for anonymous pulls."
  default     = null
  sensitive   = true
}

variable "container_registry_password" {
  type        = string
  description = "Password or token for a private registry."
  default     = null
  sensitive   = true
}

# ----------------------------------------------------------------------------
# Capacity and availability
# ----------------------------------------------------------------------------

variable "sku_name" {
  type        = string
  description = "App Service plan SKU. Premium v3 (P*v3) is recommended for production; zone redundancy requires P*v2/P*v3/P*mv3."
  default     = "P1v3"

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "P0v3", "P1v3", "P2v3", "P3v3",
      "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
    ], var.sku_name)
    error_message = "sku_name must be a supported Linux SKU: B1-B3, S1-S3, P0v3-P3v3, or P1mv3-P5mv3. Free and Shared tiers are not supported (no always-on, no health checks)."
  }
}

variable "min_instances" {
  type        = number
  description = "Minimum instance count. Defaults to 2 so the service survives a single instance failure."
  default     = 2

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 30
    error_message = "min_instances must be between 1 and 30."
  }
}

variable "max_instances" {
  type        = number
  description = "Maximum instance count for autoscale. Ignored on SKUs without autoscale (B-series), where the instance count is fixed at min_instances."
  default     = 10

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "zone_redundant" {
  type        = bool
  description = "Spread instances across availability zones. Requires a P*v2/P*v3/P*mv3 SKU and at least 2 instances. Enabled by default for production resilience."
  default     = true
}

variable "autoscale_cpu_scale_out_percent" {
  type        = number
  description = "Average plan CPU percentage above which an instance is added."
  default     = 70

  validation {
    condition     = var.autoscale_cpu_scale_out_percent > 0 && var.autoscale_cpu_scale_out_percent <= 100
    error_message = "autoscale_cpu_scale_out_percent must be in (0, 100]."
  }
}

variable "autoscale_cpu_scale_in_percent" {
  type        = number
  description = "Average plan CPU percentage below which an instance is removed."
  default     = 30

  validation {
    condition     = var.autoscale_cpu_scale_in_percent >= 0 && var.autoscale_cpu_scale_in_percent < 100
    error_message = "autoscale_cpu_scale_in_percent must be in [0, 100)."
  }
}

# ----------------------------------------------------------------------------
# Health and runtime
# ----------------------------------------------------------------------------

variable "health_check_path" {
  type        = string
  description = "HTTP path the platform polls; instances that fail repeatedly are removed from rotation. Must return 2xx when healthy."
  default     = "/healthz"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with \"/\"."
  }
}

variable "health_check_eviction_minutes" {
  type        = number
  description = "Minutes an unhealthy instance may stay unhealthy before it is replaced (2-10)."
  default     = 5

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10
    error_message = "health_check_eviction_minutes must be between 2 and 10."
  }
}

variable "app_settings" {
  type        = map(string)
  description = "Application environment variables. Treated as sensitive because they often carry secrets."
  default     = {}
  sensitive   = true
}

variable "application_insights_connection_string" {
  type        = string
  description = "Application Insights connection string, injected as APPLICATIONINSIGHTS_CONNECTION_STRING. Null disables it."
  default     = null
  sensitive   = true
}

# ----------------------------------------------------------------------------
# Rollout
# ----------------------------------------------------------------------------

variable "enable_staging_slot" {
  type        = bool
  description = "Create a \"staging\" deployment slot. Deploy new images there, verify, then swap into production."
  default     = true
}

# ----------------------------------------------------------------------------
# Observability
# ----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics workspace resource ID. When set, HTTP, console, app, and platform logs plus metrics are exported to it."
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "Retention in days for local App Service HTTP logs on the file system."
  default     = 7

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "log_retention_days must be between 1 and 365."
  }
}
