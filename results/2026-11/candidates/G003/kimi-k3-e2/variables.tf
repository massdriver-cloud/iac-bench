# -----------------------------------------------------------------------------
# Identity & placement
# -----------------------------------------------------------------------------

variable "service_name" {
  description = "Short service identifier (lowercase letters, digits, hyphens). All resource names are derived from it; 'app-<service_name>' must be globally unique across Azure."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,38}[a-z0-9])?$", var.service_name))
    error_message = "service_name must be 2-40 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group the service is deployed into. Created by the module unless create_resource_group is false."
  type        = string
}

variable "location" {
  description = "Azure region for all resources (e.g. westeurope). Pick a region that supports availability zones when zone_redundant is true."
  type        = string
}

variable "create_resource_group" {
  description = "Whether the module creates the resource group. Set to false when deploying several services into a shared, pre-existing group."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Container
# -----------------------------------------------------------------------------

variable "container_image" {
  description = "Container image with tag to run, e.g. 'payments-api:1.4.2'. Roll out a new version by deploying it to the staging slot and swapping."
  type        = string
}

variable "container_registry_url" {
  description = "Registry the image is pulled from, e.g. 'https://myregistry.azurecr.io'. Null means the default public registry (Docker Hub)."
  type        = string
  default     = null
}

variable "container_registry_id" {
  description = "Resource ID of an Azure Container Registry. When set, the app's (and slot's) system-assigned managed identity is granted AcrPull and used for image pulls — no stored registry credentials."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Capacity
# -----------------------------------------------------------------------------

variable "sku_name" {
  description = "App Service plan SKU. Defaults to Premium v3, which supports zone redundancy, autoscaling and deployment slots."
  type        = string
  default     = "P1v3"
}

variable "worker_count" {
  description = "Number of plan instances at rest; also the default capacity of the autoscale profile. Keep at least 2 when zone_redundant is true."
  type        = number
  default     = 3

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 100
    error_message = "worker_count must be between 1 and 100."
  }
}

variable "zone_redundant" {
  description = "Spread plan instances across availability zones. Requires a Premium v2/v3 SKU, a supported region and at least 2 instances."
  type        = bool
  default     = true
}

variable "autoscaling" {
  description = "CPU-based autoscaling of the plan. min_instances is the floor (2 keeps zone redundancy), max_instances the ceiling; scale out above scale_out_cpu_threshold, scale in below scale_in_cpu_threshold."
  type = object({
    enabled                 = optional(bool, true)
    min_instances           = optional(number, 2)
    max_instances           = optional(number, 10)
    scale_out_cpu_threshold = optional(number, 70)
    scale_in_cpu_threshold  = optional(number, 30)
  })
  default = {}

  validation {
    condition     = var.autoscaling.min_instances >= 1 && var.autoscaling.max_instances >= var.autoscaling.min_instances
    error_message = "Require 1 <= min_instances <= max_instances."
  }
}

# -----------------------------------------------------------------------------
# Health
# -----------------------------------------------------------------------------

variable "health_check_path" {
  description = "HTTP path App Service polls to judge instance health. Unhealthy instances leave the load balancer and are replaced after the eviction window."
  type        = string
  default     = "/health"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may fail the health check before App Service replaces it (2-10)."
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

# -----------------------------------------------------------------------------
# Rollouts
# -----------------------------------------------------------------------------

variable "staging_slot_enabled" {
  description = "Create a 'staging' deployment slot for blue-green rollouts: deploy to staging, let it warm up against the health check, then swap it into production."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "Resource ID of an existing Log Analytics workspace to receive logs and metrics. Null creates a dedicated workspace for the service."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention (days) for the Log Analytics workspace created by the module."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "sampling_percentage" {
  description = "Application Insights telemetry sampling percentage (0-100)."
  type        = number
  default     = 100

  validation {
    condition     = var.sampling_percentage >= 0 && var.sampling_percentage <= 100
    error_message = "sampling_percentage must be between 0 and 100."
  }
}

variable "daily_data_cap_gb" {
  description = "Daily Application Insights data cap in GB — a cost guardrail for chatty services."
  type        = number
  default     = 50
}

# -----------------------------------------------------------------------------
# Misc
# -----------------------------------------------------------------------------

variable "app_settings" {
  description = "Additional app settings / container environment variables. Merged over the module defaults (App Insights connection string, swap warmup settings)."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
