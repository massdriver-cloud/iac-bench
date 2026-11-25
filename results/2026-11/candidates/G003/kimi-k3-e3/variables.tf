# ---------------------------------------------------------------------------
# Identity / placement
# ---------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Base name for the service. Resource names are derived from it (asp-<name>, app-<name>, appi-<name>, log-<name>). Note: app-<name> becomes the public hostname, so it must be globally unique across Azure."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$", var.name))
    error_message = "name must be 3-50 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group the service is deployed into. Created by the module when create_resource_group is true (the default); otherwise it must already exist."
}

variable "create_resource_group" {
  type        = bool
  default     = true
  description = "Whether the module creates and owns the resource group. The standard layout is one resource group per service; set false only to deploy into a shared pre-existing group."
}

variable "location" {
  type        = string
  description = "Azure region for all resources, e.g. \"westeurope\"."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource the module creates."
}

# ---------------------------------------------------------------------------
# Workload: what to run
# ---------------------------------------------------------------------------

variable "container_image" {
  type        = string
  description = "Container image (name:tag or name@digest) to run, relative to container_registry_url, e.g. \"payments-api:1.4.2\"."
}

variable "container_registry_url" {
  type        = string
  default     = "https://mcr.microsoft.com"
  description = "Registry the image is pulled from. Defaults to the Microsoft Artifact Registry; set to your ACR (https://<name>.azurecr.io) for private images."

  validation {
    condition     = can(regex("^https://", var.container_registry_url))
    error_message = "container_registry_url must start with https://."
  }
}

variable "container_port" {
  type        = number
  default     = null
  description = "Port the container listens on (sets WEBSITES_PORT). Leave null and App Service auto-detects between 80 and 8080."
}

variable "container_registry_use_managed_identity" {
  type        = bool
  default     = false
  description = "Authenticate to the registry with the app's system-assigned managed identity (ACR only). Automatically enabled when acr_id is set."
}

variable "acr_id" {
  type        = string
  default     = null
  description = "Resource ID of an Azure Container Registry. When set, the module grants AcrPull to the app and staging slot identities and switches registry authentication to managed identity."
}

variable "app_settings" {
  type        = map(string)
  default     = {}
  description = "Extra app settings for the service. Merged over the module's built-in settings (App Insights wiring, container defaults), so explicit values win."
}

# ---------------------------------------------------------------------------
# Capacity & availability
# ---------------------------------------------------------------------------

variable "plan_sku" {
  type        = string
  default     = "P1v3"
  description = "App Service plan SKU (e.g. S1, P0v3, P1v3). Standard or higher is required for slots and autoscaling; Premium v2/v3 is required for zone redundancy."

  validation {
    condition     = !contains(["F1", "D1"], var.plan_sku)
    error_message = "Free/Shared SKUs are not supported: the module's standard features (always-on, health checks, slots, autoscaling) need Basic or higher."
  }
}

variable "zone_redundant" {
  type        = bool
  default     = true
  description = "Spread plan instances across availability zones. Requires a Premium v2/v3 (or Isolated v2) SKU and min_capacity >= 3."
}

variable "min_capacity" {
  type        = number
  default     = 3
  description = "Minimum number of plan instances the autoscaler keeps running. This is the availability floor for the service."

  validation {
    condition     = var.min_capacity >= 1 && var.min_capacity <= 30
    error_message = "min_capacity must be between 1 and 30."
  }
}

variable "default_capacity" {
  type        = number
  default     = 3
  description = "Instance count the autoscaler returns to when no scale rule applies. Must be between min_capacity and max_capacity."

  validation {
    condition     = var.default_capacity >= 1 && var.default_capacity <= 30
    error_message = "default_capacity must be between 1 and 30."
  }
}

variable "max_capacity" {
  type        = number
  default     = 10
  description = "Maximum number of plan instances the autoscaler may add. This is the cost ceiling for the service."

  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 30
    error_message = "max_capacity must be between 1 and 30."
  }
}

variable "scale_out_cpu_threshold" {
  type        = number
  default     = 70
  description = "Scale out when average CPU percentage over 5 minutes exceeds this value."
}

variable "scale_in_cpu_threshold" {
  type        = number
  default     = 30
  description = "Scale in when average CPU percentage over 15 minutes drops below this value."
}

variable "scale_out_memory_threshold" {
  type        = number
  default     = 80
  description = "Scale out when average memory percentage over 5 minutes exceeds this value."
}

variable "scale_in_memory_threshold" {
  type        = number
  default     = 50
  description = "Scale in when average memory percentage over 15 minutes drops below this value."
}

variable "scale_out_http_queue_threshold" {
  type        = number
  default     = 10
  description = "Scale out when the average HTTP queue length over 5 minutes exceeds this value (requests waiting to be served)."
}

# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

variable "health_check_path" {
  type        = string
  default     = "/healthz"
  description = "HTTP path App Service pings on every instance. Instances that fail are pulled from the load balancer (and replaced after the eviction window). Every standard service must expose a real health endpoint here."

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with \"/\"."
  }
}

variable "health_check_eviction_time_in_min" {
  type        = number
  default     = 5
  description = "Minutes an instance may fail the health check before it is replaced. Range 2-10; lower values eject sick instances faster."

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

variable "auto_heal_5xx_count" {
  type        = number
  default     = 10
  description = "Auto-heal trigger: recycle the worker when it serves more than this many HTTP 5xx responses within auto_heal_time_interval."
}

variable "auto_heal_time_interval" {
  type        = string
  default     = "00:05:00"
  description = "Auto-heal evaluation window (hh:mm:ss) for the 5xx recycle trigger."
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "enable_staging_slot" {
  type        = bool
  default     = true
  description = "Create a \"staging\" deployment slot. Standard rollout: deploy the new image to staging, wait for the health check to pass, then swap to production from your CD pipeline (az webapp deployment slot swap)."
}

variable "slot_sticky_app_settings" {
  type        = list(string)
  default     = []
  description = "Names of app settings that stay with their slot across swaps (e.g. per-slot connection strings)."
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vnet_integration_subnet_id" {
  type        = string
  default     = null
  description = "Subnet resource ID for regional VNet integration. When set, all outbound traffic from the app is routed into the VNet."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Whether the app is reachable from the public internet. Set false when fronting the service with a private ingress (e.g. Front Door with Private Link)."
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Resource ID of an existing Log Analytics workspace for diagnostics. When null the module creates a dedicated workspace for the service."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention (days) for the Log Analytics workspace the module creates."

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "enable_alerts" {
  type        = bool
  default     = true
  description = "Create the standard alert set: elevated HTTP 5xx and instances failing their health check."
}

variable "alert_action_group_ids" {
  type        = list(string)
  default     = []
  description = "Action group resource IDs notified by the standard alerts (e.g. the team's PagerDuty-backed action group)."
}

variable "alert_5xx_threshold" {
  type        = number
  default     = 25
  description = "Alert when total HTTP 5xx responses over a 5 minute window exceed this count."
}

variable "alert_health_check_threshold" {
  type        = number
  default     = 90
  description = "Alert when average HealthCheckStatus (percentage of instances passing the health check) over 5 minutes drops below this value."
}
