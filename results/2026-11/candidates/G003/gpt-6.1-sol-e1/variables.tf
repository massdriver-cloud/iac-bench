variable "name" {
  description = "Globally unique web app name; also the prefix for supporting resources."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "Use 3-40 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  description = "Name of the dedicated resource group this module creates and owns."
  type        = string
}

variable "location" {
  description = "Azure region supporting Linux Premium v3 App Service."
  type        = string
}

variable "image" {
  description = "Container image name including tag or digest, without registry hostname. Pin a digest for production."
  type        = string
  validation {
    condition     = length(trimspace(var.image)) > 0
    error_message = "Supply a nonempty container image."
  }
}

variable "registry_url" {
  description = "HTTPS registry endpoint. Private ACR uses managed identity; other private registries are not supported."
  type        = string
  default     = "https://mcr.microsoft.com"
  validation {
    condition     = can(regex("^https://[a-zA-Z0-9.-]+(:[0-9]+)?$", var.registry_url))
    error_message = "Use an HTTPS registry origin without a path or trailing slash."
  }
}

variable "acr_resource_id" {
  description = "Optional ACR resource ID. Grants both app identities AcrPull; registry_url must point to this registry. Requires permission to create role assignments."
  type        = string
  default     = null
  nullable    = true
}

variable "container_port" {
  description = "HTTP port the single container listens on (App Service terminates TLS)."
  type        = number
  default     = 8080
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer from 1 to 65535."
  }
}

variable "health_check_path" {
  description = "Unauthenticated HTTP path returning 200-299 only when ready; do not redirect to HTTPS or require auth on this path."
  type        = string
  default     = "/health"
  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}

variable "sku_name" {
  description = "Dedicated Premium v3 worker size. This plan is owned by this service, not shared across services."
  type        = string
  default     = "P1v3"
  validation {
    condition     = contains(["P1v3", "P2v3", "P3v3"], var.sku_name)
    error_message = "Choose P1v3, P2v3 or P3v3."
  }
}

variable "capacity" {
  description = "Autoscale worker bounds and initial/default capacity. Minimum two workers for instance availability."
  type = object({
    minimum = number
    default = number
    maximum = number
  })
  default = { minimum = 2, default = 2, maximum = 6 }
  validation {
    condition = (
      var.capacity.minimum >= 2 && var.capacity.minimum <= var.capacity.default &&
      var.capacity.default <= var.capacity.maximum && var.capacity.maximum <= 30 &&
      alltrue([for n in [var.capacity.minimum, var.capacity.default, var.capacity.maximum] : floor(n) == n])
    )
    error_message = "Capacity must be whole workers with 2 <= minimum <= default <= maximum <= 30."
  }
}

variable "zone_balancing_enabled" {
  description = "Distribute workers across availability zones in supported regions. Requires minimum capacity >= 3; off by default for regional portability."
  type        = bool
  default     = false
}

variable "staging_enabled" {
  description = "Create a warmed staging slot. Shares plan capacity; swaps are an explicit operator action, never automatic."
  type        = bool
  default     = true
}

variable "staging_image" {
  description = "Optional separate staging image for release validation. Null uses the production image."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Application environment variables shared by both slots. Sensitive; persisted in state. Platform-owned keys are rejected."
  type        = map(string)
  sensitive   = true
  default     = {}
  validation {
    condition = alltrue([for k in keys(var.app_settings) : !contains([
      "WEBSITES_PORT", "WEBSITES_ENABLE_APP_SERVICE_STORAGE", "WEBSITE_HEALTHCHECK_MAXPINGFAILURES",
      "APPLICATIONINSIGHTS_CONNECTION_STRING", "APPINSIGHTS_INSTRUMENTATIONKEY"
    ], upper(k))])
    error_message = "app_settings cannot override module-owned port, storage, health or telemetry settings."
  }
}

variable "slot_settings" {
  description = "Slot-specific environment variables. These keys are sticky during swaps; keys must be identical across production and staging. Do not overlap app_settings or module-owned keys."
  type = object({
    production = map(string)
    staging    = map(string)
  })
  sensitive = true
  default   = { production = {}, staging = {} }
  validation {
    condition     = toset(keys(var.slot_settings.production)) == toset(keys(var.slot_settings.staging))
    error_message = "Both slot settings maps must have the same keys."
  }
  validation {
    condition = alltrue([for k in keys(var.slot_settings.production) : !contains([
      "WEBSITES_PORT", "WEBSITES_ENABLE_APP_SERVICE_STORAGE", "WEBSITE_HEALTHCHECK_MAXPINGFAILURES",
      "APPLICATIONINSIGHTS_CONNECTION_STRING", "APPINSIGHTS_INSTRUMENTATIONKEY"
    ], upper(k))])
    error_message = "Slot settings cannot override module-owned settings."
  }
}

variable "integration_subnet_id" {
  description = "Optional existing subnet delegated to Microsoft.Web/serverFarms for outbound VNet integration. Does not make ingress private."
  type        = string
  default     = null
}

variable "alert_action_group_ids" {
  description = "Existing Azure Monitor action groups notified for high CPU and HTTP 5xx. Empty means alerts exist without notifications."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all taggable resources."
  type        = map(string)
  default     = {}
}
