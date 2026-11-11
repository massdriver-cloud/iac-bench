# ---------------------------------------------------------------------------
# Identity of the service
# ---------------------------------------------------------------------------

variable "service_name" {
  description = "Name of the service being deployed, e.g. \"orders-api\". Used as a prefix for every resource the module creates, so it must be unique per subscription."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$", var.service_name))
    error_message = "service_name must be 2-24 lowercase alphanumeric characters or hyphens, and must not start or end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment, e.g. \"dev\", \"staging\", \"prod\". Part of every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,11}$", var.environment))
    error_message = "environment must be 1-12 lowercase alphanumeric characters or hyphens, and must not start or end with a hyphen."
  }
}

variable "location" {
  description = "Azure region for all resources. Choose a region with availability zones to keep zone_redundant effective."
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "Extra tags merged on top of the module defaults (service, environment, module, managed_by)."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# The container
# ---------------------------------------------------------------------------

variable "container_image" {
  description = "Container image to run, including tag, e.g. \"myorg/orders-api:1.4.2\". The tag is the deployment artifact: bumping it and re-applying rolls out a new version."
  type        = string

  validation {
    condition     = length(trimspace(var.container_image)) > 0
    error_message = "container_image must not be empty; include the image name and tag, e.g. \"myorg/myapi:1.4.2\"."
  }
}

variable "container_registry_url" {
  description = "URL of the container registry to pull from, e.g. \"https://myregistry.azurecr.io\". Leave null for Docker Hub. For private ACR pulls, grant the app's system-assigned managed identity the AcrPull role on the registry."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on (published as WEBSITES_PORT)."
  type        = number
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "app_command_line" {
  description = "Optional command override for the container entrypoint (site_config.app_command_line). Leave null to use the image entrypoint."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

variable "sku_name" {
  description = "App Service Plan SKU. Defaults to Premium v3, which supports zone redundancy and deployment slots. Minimum instance counts for zone redundancy are enforced by the module."
  type        = string
  default     = "P1v3"
}

variable "minimum_instance_count" {
  description = "Minimum number of instances the service runs on (plan worker_count and autoscale floor). Raised to 3 automatically when zone_redundant is enabled."
  type        = number
  default     = 2

  validation {
    condition     = var.minimum_instance_count >= 1
    error_message = "minimum_instance_count must be at least 1."
  }
}

variable "maximum_instance_count" {
  description = "Maximum number of instances autoscale may scale out to."
  type        = number
  default     = 6

  validation {
    condition     = var.maximum_instance_count >= var.minimum_instance_count
    error_message = "maximum_instance_count must be greater than or equal to minimum_instance_count."
  }
}

variable "autoscale_enabled" {
  description = "Whether to create a CPU-based autoscale rule set on the service plan. When false the plan runs exactly minimum_instance_count workers."
  type        = bool
  default     = true
}

variable "scale_out_cpu_threshold" {
  description = "Average CPU percentage (5m window) above which one instance is added."
  type        = number
  default     = 70
}

variable "scale_in_cpu_threshold" {
  description = "Average CPU percentage (5m window) below which one instance is removed. Scale-in uses a longer cooldown than scale-out on purpose."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# Availability
# ---------------------------------------------------------------------------

variable "zone_redundant" {
  description = "Spread plan instances across availability zones (requires a zone-capable region and SKU; the module enforces a 3-instance floor). Disable only for regions/SKUs that cannot support it."
  type        = bool
  default     = true
}

variable "always_on" {
  description = "Keep the app loaded so requests never pay a cold-start. Recommended for production HTTP APIs."
  type        = bool
  default     = true
}

variable "https_only" {
  description = "Reject plain-HTTP requests. Leave enabled unless you have a very specific reason not to."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Whether the app accepts inbound traffic from the public internet. Set false when fronting the app with private endpoints / private link only."
  type        = bool
  default     = true
}

variable "virtual_network_subnet_id" {
  description = "Optional subnet resource ID for VNet integration (outbound traffic from the app). Also enables vnet_route_all_enabled so all egress goes through the VNet."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

variable "health_check_enabled" {
  description = "Enable App Service health checks: the platform probes each instance and replaces instances that stop answering."
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Path the health probe hits, e.g. \"/healthz\". It should return 2xx only when the service can genuinely serve traffic."
  type        = string
  default     = "/healthz"
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may fail health checks before it is evicted and replaced (2-10)."
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10 minutes."
  }
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "staging_slot_enabled" {
  description = "Create a deployment slot for staged rollouts: deploy the new image there, verify, then swap. Requires a Standard-or-higher SKU."
  type        = bool
  default     = true
}

variable "staging_slot_name" {
  description = "Name of the deployment slot used for staged rollouts."
  type        = string
  default     = "staging"
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "Optional existing Log Analytics workspace resource ID. When null the module creates a dedicated workspace for the service."
  type        = string
  default     = null
}

variable "log_analytics_retention_days" {
  description = "Retention in days for the Log Analytics workspace the module creates (also used for the workspace-based Application Insights)."
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "log_analytics_retention_days must be between 30 and 730."
  }
}

# ---------------------------------------------------------------------------
# Security and operations
# ---------------------------------------------------------------------------

variable "managed_identity_enabled" {
  description = "Give the app a system-assigned managed identity, for keyless access to registries (AcrPull), Key Vault, and other Azure resources."
  type        = bool
  default     = true
}

variable "management_lock_enabled" {
  description = "Apply a CanNotDelete lock to the web app so it can only be removed through this module."
  type        = bool
  default     = true
}

variable "extra_app_settings" {
  description = "Additional app settings merged over the defaults, e.g. LOG_LEVEL = \"info\". Values must be strings."
  type        = map(string)
  default     = {}
}
