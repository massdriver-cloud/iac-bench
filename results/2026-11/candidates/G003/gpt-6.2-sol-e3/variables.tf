variable "name" {
  description = "Globally unique App Service name; also used as the prefix for owned resources. Use 3–45 lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,43}[a-z0-9]$", var.name))
    error_message = "Provide a 3–45 character DNS-safe name starting with a lowercase letter and ending with a lowercase letter or digit."
  }
}

variable "location" {
  description = "Azure region for the service. Choose a region that supports the selected Premium v3 tier and availability zones if enabled."
  type        = string
  nullable    = false
}

variable "container_image" {
  description = "Production image name relative to the registry (for example, team/api:1.2.3 or team/api@sha256:...). Prefer an immutable tag or digest."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.container_image)) > 0 && !can(regex("\\s|://", var.container_image))
    error_message = "Provide an image reference without whitespace or a URL scheme."
  }
}

variable "public_registry_url" {
  description = "HTTPS URL for the image registry when acr is not set. Defaults to Docker Hub."
  type        = string
  default     = "https://index.docker.io"
  nullable    = false

  validation {
    condition     = can(regex("^https://[^/[:space:]]+$", var.public_registry_url))
    error_message = "Use an HTTPS registry URL containing only the host and optional port, without a trailing slash."
  }
}

variable "acr" {
  description = "Optional existing, network-reachable Azure Container Registry in RBAC Registry Permissions mode. The module assigns AcrPull to a dedicated managed identity."
  type = object({
    id           = string
    login_server = string
  })
  default = null

  validation {
    condition     = var.acr == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ContainerRegistry/registries/[^/]+$", var.acr.id)) && can(regex("^[a-zA-Z0-9.-]+$", var.acr.login_server))
    error_message = "Supply the ACR resource ID and its login server hostname (without a scheme or path)."
  }
}

variable "container_port" {
  description = "HTTP port that the Linux container listens on (on all interfaces)."
  type        = number
  default     = 80
  nullable    = false

  validation {
    condition     = var.container_port == floor(var.container_port) && var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be an integer from 1 through 65535."
  }
}

variable "health_check_path" {
  description = "Unauthenticated readiness path for live health checks and startup/swap warmup. It should return HTTP 200 or 204 when ready, without a redirect."
  type        = string
  default     = "/"
  nullable    = false

  validation {
    condition     = can(regex("^/[^[:space:]?#]*$", var.health_check_path)) && !startswith(var.health_check_path, "//")
    error_message = "health_check_path must be an absolute HTTP path without a query, fragment, or whitespace."
  }
}

variable "capacity" {
  description = "Instance size (small/medium/large) and CPU autoscale bounds. Zone redundancy requires at least two instances."
  type = object({
    size           = optional(string, "small")
    minimum        = optional(number, 2)
    maximum        = optional(number, 5)
    zone_redundant = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition = (
      contains(["small", "medium", "large"], var.capacity.size) &&
      var.capacity.minimum == floor(var.capacity.minimum) && var.capacity.maximum == floor(var.capacity.maximum) &&
      var.capacity.minimum >= (var.capacity.zone_redundant ? 2 : 1) &&
      var.capacity.maximum > var.capacity.minimum && var.capacity.maximum <= 30
    )
    error_message = "Use small, medium, or large and whole-number bounds with maximum greater than minimum and at most 30. Minimum is 2 for zone redundancy and 1 otherwise."
  }
}

variable "create_staging_slot" {
  description = "Create a restricted staging slot on the same plan for warmup and manual swaps."
  type        = bool
  default     = true
  nullable    = false
}

variable "staging_image" {
  description = "Optional candidate image for staging, relative to the same registry; defaults to container_image."
  type        = string
  default     = null

  validation {
    condition     = var.staging_image == null ? true : length(trimspace(var.staging_image)) > 0 && !can(regex("\\s|://", var.staging_image))
    error_message = "Provide an image reference without whitespace or a URL scheme, or leave staging_image unset."
  }
}

variable "staging_allowed_cidrs" {
  description = "CIDRs allowed to send HTTP requests to staging. Empty denies external requests; SCM remains blocked."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.staging_allowed_cidrs) <= 50 && alltrue([for cidr in var.staging_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Provide up to 50 valid IPv4 or IPv6 CIDRs."
  }
}

variable "app_settings" {
  description = "Additional settings shared between production and staging. Use Key Vault references instead of secret values. Platform-managed settings take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "staging_app_settings" {
  description = "Overrides for staging. These keys are automatically sticky across slot swaps. Platform-managed settings take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace resource ID. If unset, create a dedicated workspace with 30 days of retention."
  type        = string
  default     = null
}

variable "alert_action_group_ids" {
  description = "Existing Azure Monitor action group IDs to notify for production alerts. Without these, alerts are visible in Azure Monitor but do not page."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.alert_action_group_ids) <= 5
    error_message = "Azure Monitor supports up to five action groups per metric alert."
  }
}

variable "tags" {
  description = "Tags for owned Azure resources that support tagging."
  type        = map(string)
  default     = {}
  nullable    = false
}
