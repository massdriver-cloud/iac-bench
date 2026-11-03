# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Base name for the service. Used to derive the names of the App Service plan, web app, deployment slot and monitoring resources."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$", var.name))
    error_message = "name must be 2-40 characters of lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group the module creates and deploys into."
}

variable "location" {
  type        = string
  description = "Azure region to deploy into, e.g. \"eastus\"."
}

variable "tags" {
  type        = map(string)
  description = "Additional tags applied to every resource the module creates."
  default     = {}
}

variable "web_app_name" {
  type        = string
  description = "Explicit, globally unique web app name. When null the module derives \"<name>-<random suffix>\" so the azurewebsites.net hostname never collides between services."
  default     = null
}

# ---------------------------------------------------------------------------
# Capacity & availability
# ---------------------------------------------------------------------------

variable "sku_name" {
  type        = string
  description = "App Service plan SKU. Defaults to Premium v3 so zone redundancy, deployment slots and 30-instance autoscale are available. Use \"S1\" where Premium v3 quota or region availability is a constraint; slots/autoscale are disabled automatically on Free/Shared/Basic."
  default     = "P0v3"
}

variable "instance_count" {
  type        = number
  description = "Initial number of workers in the plan. Also used as the autoscale default capacity. Must be at least 3 when zone_redundant is true."
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 30
    error_message = "instance_count must be between 1 and 30."
  }
}

variable "zone_redundant" {
  type        = bool
  description = "Spread plan instances across availability zones. Requires a Premium v2/v3 SKU and at least 3 instances (enforced by a plan precondition)."
  default     = false
}

variable "autoscale_enabled" {
  type        = bool
  description = "Attach a CPU-based autoscale profile to the plan. Ignored automatically on tiers that do not support autoscale (Free/Shared/Basic)."
  default     = true
}

variable "autoscale_min_instances" {
  type        = number
  description = "Minimum workers autoscale will keep running."
  default     = 2

  validation {
    condition     = var.autoscale_min_instances >= 1 && var.autoscale_min_instances <= 30
    error_message = "autoscale_min_instances must be between 1 and 30."
  }
}

variable "autoscale_max_instances" {
  type        = number
  description = "Maximum workers autoscale will add. Standard SKUs cap at 10; Premium v3 caps at 30."
  default     = 10

  validation {
    condition     = var.autoscale_max_instances >= 1 && var.autoscale_max_instances <= 30
    error_message = "autoscale_max_instances must be between 1 and 30."
  }
}

variable "autoscale_scale_out_cpu_threshold" {
  type        = number
  description = "Average plan CPU percentage over 10 minutes that triggers a scale-out."
  default     = 70

  validation {
    condition     = var.autoscale_scale_out_cpu_threshold >= 1 && var.autoscale_scale_out_cpu_threshold <= 99
    error_message = "autoscale_scale_out_cpu_threshold must be between 1 and 99."
  }
}

variable "autoscale_scale_in_cpu_threshold" {
  type        = number
  description = "Average plan CPU percentage over 10 minutes that triggers a scale-in."
  default     = 30

  validation {
    condition     = var.autoscale_scale_in_cpu_threshold >= 1 && var.autoscale_scale_in_cpu_threshold <= 99
    error_message = "autoscale_scale_in_cpu_threshold must be between 1 and 99."
  }
}

# ---------------------------------------------------------------------------
# Container & runtime
# ---------------------------------------------------------------------------

variable "container_image" {
  type        = string
  description = "Container image (with tag) the app boots with, e.g. \"myregistry.azurecr.io/orders-api:1.4.2\". Day-2 image bumps are expected to come from CI/CD; the module ignores drift on this attribute after creation."
  default     = "mcr.microsoft.com/appsvc/staticsite:latest"
}

variable "container_registry_url" {
  type        = string
  description = "Registry URL including scheme, e.g. \"https://myregistry.azurecr.io\" or \"https://index.docker.io\"."
  default     = "https://mcr.microsoft.com"
}

variable "container_registry_id" {
  type        = string
  description = "Resource ID of an Azure Container Registry. When set, the app and slot pull images with their managed identities and are granted AcrPull on the registry. Leave null for public registries."
  default     = null
}

variable "container_port" {
  type        = number
  description = "Port the container listens on. Set as WEBSITES_PORT so the platform routes traffic correctly."
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}

variable "app_settings" {
  type        = map(string)
  description = "Additional app settings, merged over the module defaults (App Insights wiring, WEBSITES_PORT, container hardening). Keys here win on conflict."
  default     = {}
}

variable "always_on" {
  type        = bool
  description = "Keep the app warm. Recommended for container workloads to avoid cold starts. Automatically disabled on Free/Shared SKUs which do not support it."
  default     = true
}

# ---------------------------------------------------------------------------
# Health & self-healing
# ---------------------------------------------------------------------------

variable "health_check_path" {
  type        = string
  description = "Path the platform polls to decide instance health, e.g. \"/healthz\". Unhealthy instances are removed from rotation and replaced."
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must be an absolute path starting with \"/\"."
  }
}

variable "health_check_eviction_time_in_min" {
  type        = number
  description = "Minutes an instance may fail the health check before the platform replaces it."
  default     = 5

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

variable "auto_heal_enabled" {
  type        = bool
  description = "Recycle the worker process when it serves a sustained burst of 5xx responses. A blunt but effective mitigation for wedged processes."
  default     = true
}

variable "auto_heal_status_code_count" {
  type        = number
  description = "Number of 500-599 responses within 5 minutes that triggers the auto-heal recycle."
  default     = 20

  validation {
    condition     = var.auto_heal_status_code_count >= 1
    error_message = "auto_heal_status_code_count must be at least 1."
  }
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "staging_slot_enabled" {
  type        = bool
  description = "Create a staging deployment slot for blue/green or canary rollouts. CI/CD deploys to the slot and swaps; the slot mirrors the production configuration. Disabled automatically on Free/Shared/Basic SKUs which have no slots."
  default     = true
}

variable "staging_slot_name" {
  type        = string
  description = "Name of the deployment slot."
  default     = "staging"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,59}$", var.staging_slot_name))
    error_message = "staging_slot_name must be 1-59 characters of letters, digits and hyphens."
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vnet_integration_subnet_id" {
  type        = string
  description = "Optional subnet ID (delegated to Microsoft.Web/serverFarms) for regional VNet integration, so the app can reach private dependencies."
  default     = null
}

variable "vnet_route_all_enabled" {
  type        = bool
  description = "Force all outbound traffic through the integrated VNet (only meaningful with vnet_integration_subnet_id)."
  default     = false
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  type        = number
  description = "Retention for the Log Analytics workspace backing logs and metrics."
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "app_log_level" {
  type        = string
  description = "Filesystem application log level captured by the platform."
  default     = "Information"

  validation {
    condition     = contains(["Off", "Error", "Warning", "Information", "Verbose"], var.app_log_level)
    error_message = "app_log_level must be one of Off, Error, Warning, Information, Verbose."
  }
}

variable "http_log_retention_days" {
  type        = number
  description = "Days to retain web server (HTTP) logs on the filesystem."
  default     = 7

  validation {
    condition     = var.http_log_retention_days >= 1 && var.http_log_retention_days <= 99
    error_message = "http_log_retention_days must be between 1 and 99."
  }
}

variable "alerts_enabled" {
  type        = bool
  description = "Create the standard alert set (HTTP 5xx spike, elevated response time) and an action group."
  default     = true
}

variable "alert_email_addresses" {
  type        = list(string)
  description = "Email receivers attached to the alert action group, e.g. the on-call distribution list."
  default     = []
}

variable "http5xx_alert_threshold" {
  type        = number
  description = "Total HTTP 5xx responses within 5 minutes that raises the severity-2 alert."
  default     = 10
}

variable "response_time_alert_threshold_seconds" {
  type        = number
  description = "Average response time (seconds) over 5 minutes that raises the severity-3 alert."
  default     = 10
}
