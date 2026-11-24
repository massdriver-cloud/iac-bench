variable "name" {
  description = "Globally unique App Service name, also used as the base name for supporting resources. Use a stable service-and-environment name."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "Use 3–40 lowercase letters, digits, or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region for this service and its supporting resources."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.location) != ""
    error_message = "Specify an Azure region."
  }
}

variable "container" {
  description = "Image repository and version without the registry hostname, HTTPS registry URL, and optionally the resource ID of an existing Azure Container Registry to pull from with managed identity."
  type = object({
    image        = string
    registry_url = optional(string, "https://index.docker.io")
    acr_id       = optional(string)
    port         = optional(number, 8080)
  })
  nullable = false

  validation {
    condition = try(
      can(regex("^[a-z0-9._-]+(/[a-z0-9._-]+)*(:[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.container.image)) &&
      can(regex("^https://[a-zA-Z0-9.-]+(:[0-9]+)?$", var.container.registry_url)) &&
      var.container.port >= 1 && var.container.port <= 65535 && floor(var.container.port) == var.container.port &&
      (var.container.acr_id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerRegistry/registries/[^/]+$", var.container.acr_id))),
      false
    )
    error_message = "Specify a versioned image repository, an HTTPS registry URL with no path, a valid TCP port, and (if used) the full ACR resource ID."
  }
}

variable "health_path" {
  description = "Unauthenticated readiness endpoint used for health checks, startup and slot warm-up. Return HTTP 200 when ready."
  type        = string
  default     = "/healthz"
  nullable    = false

  validation {
    condition     = can(regex("^/[^[:space:]?#]*$", var.health_path)) && !startswith(var.health_path, "//")
    error_message = "The health path must be an absolute URL path with no query string or fragment."
  }
}

variable "capacity" {
  description = "Premium v3 plan size, autoscale worker bounds and optional Azure Availability Zone redundancy. The minimum is also the starting and fallback capacity."
  type = object({
    sku            = optional(string, "P1v3")
    minimum        = optional(number, 2)
    maximum        = optional(number, 5)
    zone_redundant = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition = contains(["P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3"], var.capacity.sku) && (
      floor(var.capacity.minimum) == var.capacity.minimum && floor(var.capacity.maximum) == var.capacity.maximum &&
      var.capacity.minimum >= (var.capacity.zone_redundant ? 2 : 1) &&
      var.capacity.maximum >= var.capacity.minimum && var.capacity.maximum <= 30
    )
    error_message = "Use a supported Premium v3 SKU and integer bounds 1 <= minimum <= maximum <= 30. Zone redundancy requires at least two workers and a supported deployment region and stamp."
  }
}

variable "staging" {
  description = "Set to an object to provision a staging slot. Its optional image overrides the production image and must use the same registry. External requests are denied unless an allowed CIDR matches."
  type = object({
    image         = optional(string)
    app_settings  = optional(map(string), {})
    allowed_cidrs = optional(set(string), [])
  })
  default = null

  validation {
    condition = var.staging == null ? true : (
      (var.staging.image == null ? true : can(regex("^[a-z0-9._-]+(/[a-z0-9._-]+)*(:[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.staging.image))) &&
      alltrue([for cidr in var.staging.allowed_cidrs : can(cidrhost(cidr, 0))])
    )
    error_message = "Provide valid CIDR ranges and a versioned staging image if overriding the production image."
  }
}

variable "app_settings" {
  description = "Service-specific app settings. Use Key Vault reference strings rather than literal secrets. Platform settings owned by the module take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "sticky_app_setting_names" {
  description = "App setting names that should stay with their slot during a swap."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "integration_subnet_id" {
  description = "Optional existing subnet delegated to Microsoft.Web/serverFarms for outbound VNet integration, in the same region."
  type        = string
  default     = null
}

variable "action_group_ids" {
  description = "Azure Monitor action group IDs to notify on production HTTP 5xx alerts. Leave empty to omit the alert."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "tags" {
  description = "Tags to apply to resources owned by this module."
  type        = map(string)
  default     = {}
  nullable    = false
}
