# ---------------------------------------------------------------------------
# Identity / placement
# ---------------------------------------------------------------------------

variable "name" {
  description = "Service name. Used as the base for all resource names; the web app hostname becomes <name>.azurewebsites.net, so it must be globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 chars of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "location" {
  description = "Azure region for all resources (e.g. \"eastus2\"). Must support availability zones when zone_redundant = true."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into. If null, a resource group named rg-<name> is created."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Workload
# ---------------------------------------------------------------------------

variable "container_image" {
  description = "Production container image as repository:tag (or repository@digest), without the registry host, e.g. \"team/orders-api:1.4.2\"."
  type        = string
}

variable "container_registry_url" {
  description = "Registry URL including scheme, e.g. \"https://myregistry.azurecr.io\"."
  type        = string
  default     = "https://mcr.microsoft.com"

  validation {
    condition     = can(regex("^https://", var.container_registry_url))
    error_message = "container_registry_url must start with https://."
  }
}

variable "container_registry_id" {
  description = "Resource ID of an Azure Container Registry. If set, the app's managed identity is granted AcrPull on it and images are pulled with that identity (no registry passwords)."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on for HTTP traffic."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}

variable "app_settings" {
  description = "Non-secret environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "secret_app_settings" {
  description = "Secret environment variables for the container (values may be Key Vault references: @Microsoft.KeyVault(SecretUri=...), resolved with the app's managed identity)."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Capacity / availability
# ---------------------------------------------------------------------------

variable "sku_name" {
  description = "App Service plan SKU (instance size). Premium v3 (P0v3/P1v3/P2v3/P3v3, P1mv3...) is required for zone redundancy."
  type        = string
  default     = "P1v3"
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires a Premium v3 SKU, a region with zones, and min_instances >= 2. Cannot be changed after creation without replacing the plan."
  type        = bool
  default     = true
}

variable "min_instances" {
  description = "Minimum (and baseline) instance count. Autoscale never goes below this."
  type        = number
  default     = 3

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 30
    error_message = "min_instances must be between 1 and 30."
  }
}

variable "max_instances" {
  description = "Maximum instance count autoscale may reach."
  type        = number
  default     = 10

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "autoscale_enabled" {
  description = "Enable CPU/memory based autoscale on the plan between min_instances and max_instances."
  type        = bool
  default     = true
}

variable "scale_out_cpu_percent" {
  description = "Average CPU percentage (5 min) above which an instance is added."
  type        = number
  default     = 70
}

variable "scale_in_cpu_percent" {
  description = "Average CPU percentage (10 min) below which an instance is removed."
  type        = number
  default     = 30
}

variable "scale_out_memory_percent" {
  description = "Average memory percentage (5 min) above which an instance is added."
  type        = number
  default     = 80
}

# ---------------------------------------------------------------------------
# Health / rollouts
# ---------------------------------------------------------------------------

variable "health_check_path" {
  description = "HTTP path App Service probes on each instance. Unhealthy instances are removed from the load balancer and replaced; the same path is used to warm up the staging slot before a swap. Should return 200 only when the instance can serve traffic."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_minutes" {
  description = "Minutes an instance may fail health checks before it is replaced (2-10)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10
    error_message = "health_check_eviction_minutes must be between 2 and 10."
  }
}

variable "staging_slot_enabled" {
  description = "Create a 'staging' deployment slot (same plan, same settings) for pre-release verification and warmed-up swaps."
  type        = bool
  default     = true
}

variable "staging_container_image" {
  description = "Image to run in the staging slot (repository:tag). Null means the same as container_image. Rollout: set this to the candidate, verify on the staging URL, then promote by setting container_image to the same value."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vnet_integration_subnet_id" {
  description = "Subnet ID (delegated to Microsoft.Web/serverFarms) for outbound VNet integration; all outbound traffic is then routed through the VNet. Null disables integration."
  type        = string
  default     = null
}

variable "allowed_inbound_cidrs" {
  description = "If non-empty, inbound traffic is restricted to these CIDRs (all other traffic denied). Empty means publicly reachable."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace ID for logs, metrics and Application Insights. If null, a workspace is created."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention (days) for the module-created Log Analytics workspace."
  type        = number
  default     = 30
}

variable "alert_action_group_ids" {
  description = "Action group IDs notified by the module's alerts. Alerts are still created (visible in Azure Monitor) when empty."
  type        = list(string)
  default     = []
}

variable "alert_http_5xx_threshold" {
  description = "Number of HTTP 5xx responses in 5 minutes that triggers an alert."
  type        = number
  default     = 10
}

variable "alert_response_time_seconds" {
  description = "Average response time (seconds) over 5 minutes that triggers an alert."
  type        = number
  default     = 2
}
