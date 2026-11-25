variable "name" {
  description = "Globally unique App Service name. Also used as the prefix for supporting resources."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Use 3–40 lowercase letters, digits, or single hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region supporting the selected App Service SKU."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) > 0 && var.location == trimspace(var.location)
    error_message = "Specify an Azure region without surrounding whitespace."
  }
}

variable "image" {
  description = "Initial Linux OCI image, separated into an HTTPS registry URL and repository with explicit tag or sha256 digest. With acr_id set, registry_url must be that registry's login server."
  type = object({
    registry_url = string
    repository   = string
  })
  nullable = false

  validation {
    condition = (can(regex("^https://[a-zA-Z0-9][a-zA-Z0-9.-]*(:[0-9]+)?$", var.image.registry_url)) &&
      can(regex("^([a-z0-9]+(([._]|__|-+)[a-z0-9]+)*/)*[a-z0-9]+(([._]|__|-+)[a-z0-9]+)*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}|@sha256:[a-f0-9]{64})$", var.image.repository))
    )
    error_message = "Use an HTTPS registry URL without a path and a repository with an explicit tag or sha256 digest."
  }
}

variable "acr_id" {
  description = "Existing Azure Container Registry resource ID. If set, grant a dedicated managed identity AcrPull. If omitted, use an anonymous registry. The registry must use registry-wide RBAC, not ABAC repository permissions."
  type        = string
  default     = null

  validation {
    condition     = var.acr_id == null ? true : can(regex("(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft.ContainerRegistry/registries/[a-z0-9]+$", var.acr_id))
    error_message = "acr_id must be an Azure Container Registry resource ID."
  }
}

variable "container_port" {
  description = "HTTP port on which the container listens on all interfaces."
  type        = number
  default     = 8080
  nullable    = false

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "health_check_path" {
  description = "Unauthenticated HTTP readiness endpoint. It must return 200 once the container can serve traffic."
  type        = string
  default     = "/healthz"
  nullable    = false

  validation {
    condition     = can(regex("^/([^/[:space:]?#][^[:space:]?#]*)?$", var.health_check_path))
    error_message = "Use an absolute path without whitespace, a query, or a fragment."
  }
}

variable "sku_name" {
  description = "Premium v3 plan SKU. Choose a size based on memory and CPU needs."
  type        = string
  default     = "P1v3"
  nullable    = false

  validation {
    condition     = contains(["P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3"], var.sku_name)
    error_message = "Choose a supported Premium v3 SKU."
  }
}

variable "capacity" {
  description = "Autoscale worker bounds and fallback worker count. Set all three equal for fixed capacity."
  type = object({
    minimum = number
    default = number
    maximum = number
  })
  default  = { minimum = 2, default = 2, maximum = 5 }
  nullable = false

  validation {
    condition = try(
      alltrue([for n in [var.capacity.minimum, var.capacity.default, var.capacity.maximum] : n == floor(n) && n >= 1 && n <= 30]) &&
      var.capacity.minimum <= var.capacity.default && var.capacity.default <= var.capacity.maximum,
      false
    )
    error_message = "Capacity counts must be integers from 1 to 30, ordered minimum <= default <= maximum."
  }
}

variable "zone_redundant" {
  description = "Enable zone balancing on supported App Service stamps. Requires at least two workers."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_staging_slot" {
  description = "Create a staging slot on the same plan for warmup, validation, and swap-based releases."
  type        = bool
  default     = true
  nullable    = false
}

variable "staging_allowed_cidrs" {
  description = "Public IPv4 CIDRs allowed to reach staging. Empty means deny all external staging requests."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.staging_allowed_cidrs) <= 512 && alltrue([for cidr in var.staging_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "Provide up to 512 valid IPv4 CIDRs."
  }
}

variable "app_settings" {
  description = "Additional application settings shared by production and staging. Use Key Vault references, not secret values. Runtime identities must be authorized separately."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for value in values(var.app_settings) : value != null])
    error_message = "App setting values must be non-null."
  }
}

variable "environment_settings" {
  description = "Per-slot application settings that stay with the slot during swaps and override app_settings. Supply references, not secret values. The staging value is unused if staging is disabled."
  type = map(object({
    production = string
    staging    = string
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for entry in values(var.environment_settings) : try(entry.production != null && entry.staging != null, false)])
    error_message = "Each environment setting must have non-null production and staging values."
  }
}

variable "alert_action_group_ids" {
  description = "Existing Azure Monitor action group resource IDs to notify for production alerts. Empty means alerts are visible only in Azure Monitor."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for id in var.alert_action_group_ids : can(regex("(?i)^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft.Insights/actionGroups/[^/]+$", id))])
    error_message = "Each action group must be specified by its Azure resource ID."
  }
}

variable "log_retention_days" {
  description = "Default Log Analytics workspace retention in days. Azure Monitor table-specific retention can differ."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.log_retention_days)
    error_message = "Use 30, 60, 90, 120, 180, 270, 365, 550, or 730 days."
  }
}

variable "tags" {
  description = "Tags applied to resources that support them."
  type        = map(string)
  default     = {}
  nullable    = false
}
