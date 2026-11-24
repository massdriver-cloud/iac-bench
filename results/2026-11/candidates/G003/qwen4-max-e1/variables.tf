# ---------------------------------------------------------------------------
# Identity of the service (required)
# ---------------------------------------------------------------------------

variable "name" {
  description = "Service name. Used as the globally-unique Web App name and as the prefix for every supporting resource (plan, resource group, insights, workspace)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-60 characters, alphanumeric or hyphens, and must start and end with an alphanumeric character (Azure Web App naming rules)."
  }
}

variable "location" {
  description = "Azure region the service runs in."
  type        = string
}

variable "container_image" {
  description = "Container image to run, in repository/image:tag form (e.g. myacr.azurecr.io/orders-api:1.4.2 or nginx:alpine). Pin a tag or digest; avoid :latest for production services."
  type        = string
}

# ---------------------------------------------------------------------------
# Container / registry
# ---------------------------------------------------------------------------

variable "container_registry_url" {
  description = "Registry base URL, e.g. https://myacr.azurecr.io. Defaults to Docker Hub for public images."
  type        = string
  default     = "https://index.docker.io"
}

variable "container_port" {
  description = "Port the container listens on. Wired to WEBSITES_PORT so App Service routes traffic correctly."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "acr_id" {
  description = "Resource ID of an Azure Container Registry. When set, the app (and staging slot) pull images with their managed identities and an AcrPull role assignment is created. Set container_registry_url to https://<registry>.azurecr.io as well."
  type        = string
  default     = null
}

variable "registry_username" {
  description = "Username for a non-ACR private registry (basic auth). Prefer acr_id / managed identity where possible."
  type        = string
  default     = null
}

variable "registry_password" {
  description = "Password/token for a non-ACR private registry (basic auth)."
  type        = string
  default     = null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

variable "sku_name" {
  description = "App Service Plan SKU. Production default is P1v3 (Premium v3). Use P*v3 for zone redundancy; B* only for cheap non-production services."
  type        = string
  default     = "P1v3"
}

variable "instance_count" {
  description = "Initial/default worker count. With autoscale enabled this is the autoscale profile's default capacity; afterwards Azure autoscale owns the live count."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1
    error_message = "instance_count must be at least 1."
  }
}

variable "zone_redundant" {
  description = "Spread plan workers across availability zones. Requires a Premium v2/v3 SKU and at least 3 workers (the module raises capacity to 3 automatically)."
  type        = bool
  default     = false
}

variable "autoscale_enabled" {
  description = "Manage CPU-based autoscale rules on the plan (scale out above cpu_scale_out_threshold, in below cpu_scale_in_threshold)."
  type        = bool
  default     = true
}

variable "autoscale_min" {
  description = "Minimum worker count for autoscale."
  type        = number
  default     = 1
}

variable "autoscale_max" {
  description = "Maximum worker count for autoscale."
  type        = number
  default     = 5
}

variable "cpu_scale_out_threshold" {
  description = "Average plan CPU percentage that triggers a scale-out (+1 worker)."
  type        = number
  default     = 70
}

variable "cpu_scale_in_threshold" {
  description = "Average plan CPU percentage that triggers a scale-in (-1 worker)."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Health & availability
# ---------------------------------------------------------------------------

variable "health_check_path" {
  description = "HTTP path App Service probes on every instance. Unhealthy instances are rotated out of the load balancer. Must return 2xx when the service is ready to serve."
  type        = string
  default     = "/healthz"
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may fail health checks before it is evicted/replaced (2-10)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

variable "subnet_id" {
  description = "Subnet ID for regional VNet integration (delegated to Microsoft.Web/serverFarms). When set, all outbound traffic is routed into the VNet."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "enable_staging_slot" {
  description = "Create a 'staging' deployment slot for blue/green rollouts on the same plan. Deploy the new image to staging, warm it up, then swap."
  type        = bool
  default     = true
}

variable "auto_swap_enabled" {
  description = "Automatically swap the staging slot into production after a successful deployment/warm-up. Off by default: SREs swap explicitly after verifying staging."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

variable "app_settings" {
  description = "Application configuration (env vars) merged over the module-managed settings. Do not put WEBSITES_PORT here; use container_port."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "slot_app_settings" {
  description = "Extra/overriding app settings for the staging slot only (e.g. pointing at a staging database)."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "sticky_app_setting_names" {
  description = "App setting names that stay pinned to their slot during a swap (slot-specific configuration)."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "enable_app_insights" {
  description = "Create a workspace-based Application Insights component and inject APPLICATIONINSIGHTS_CONNECTION_STRING into the app."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of an existing central Log Analytics workspace. When null the module creates a dedicated workspace for the service."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention (days) for the module-created Log Analytics workspace. Ignored when log_analytics_workspace_id is supplied."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Governance
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
