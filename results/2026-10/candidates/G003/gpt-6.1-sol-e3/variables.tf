variable "name" {
  description = "Globally unique app name; also used as the resource naming prefix."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,38}[a-z0-9]$", var.name))
    error_message = "Use 4-40 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region supporting the selected SKU and optional zone redundancy."
  type        = string
  default     = "eastus"
}

variable "container" {
  description = "Container image (prefer an immutable digest), registry endpoint and listening port. For private ACR, supply registry_resource_id to grant AcrPull to both app identities."
  type = object({
    image                = string
    registry_url         = optional(string, "https://index.docker.io")
    registry_resource_id = optional(string)
    port                 = optional(number, 8080)
  })
  validation {
    condition     = length(var.container.image) > 0 && startswith(var.container.registry_url, "https://") && var.container.port >= 1 && var.container.port <= 65535 && floor(var.container.port) == var.container.port
    error_message = "Provide an image, an HTTPS registry URL, and an integer TCP port."
  }
}

variable "capacity" {
  description = "Dedicated Premium v3 capacity. Autoscale is CPU based; default_instances is also the initial plan size. Zone redundancy requires at least two workers and regional support."
  type = object({
    sku               = optional(string, "P1v3")
    default_instances = optional(number, 2)
    min_instances     = optional(number, 2)
    max_instances     = optional(number, 6)
    autoscale_enabled = optional(bool, true)
    zone_redundant    = optional(bool, false)
  })
  default = {}
  validation {
    condition = contains(["P0v3", "P1v3", "P2v3", "P3v3"], var.capacity.sku) && alltrue([
      for n in [var.capacity.min_instances, var.capacity.default_instances, var.capacity.max_instances] : n >= 1 && n <= 30 && floor(n) == n
    ]) && var.capacity.min_instances <= var.capacity.default_instances && var.capacity.default_instances <= var.capacity.max_instances && (!var.capacity.zone_redundant || var.capacity.min_instances >= 2)
    error_message = "Use a supported Premium v3 SKU and integer worker counts 1-30 with min <= default <= max; zone redundancy requires min >= 2."
  }
}

variable "health_check_path" {
  description = "Unauthenticated readiness endpoint returning 200-299 without redirects. Used for worker health and slot warm-up."
  type        = string
  default     = "/health"
  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "Health check path must begin with /."
  }
}

variable "staging_enabled" {
  description = "Create a staging slot for explicit, operator-controlled swaps. No automatic traffic shifting or swap."
  type        = bool
  default     = true
}

variable "staging_image" {
  description = "Optional separate staging image, using the same registry and port. Null uses the production image."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Application-specific settings. Platform settings managed by this module take precedence. Prefer Key Vault references to literal secrets."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "slot_sticky_setting_names" {
  description = "Additional app setting names that stay with the slot during swaps (for example database Key Vault references)."
  type        = list(string)
  default     = []
}

variable "integration_subnet_id" {
  description = "Optional subnet delegated to Microsoft.Web/serverFarms for outbound VNet integration. Size it for both slots and scale-out."
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = "Allow public inbound access. Disabling requires separately provisioned private endpoints and private DNS. Outbound VNet integration does not provide inbound connectivity."
  type        = bool
  default     = true
}

variable "allowed_inbound_cidrs" {
  description = "Optional IPv4/IPv6 CIDR allow-list applied to both app and SCM endpoints; empty permits all public sources. Include deployment agents when restricting SCM."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.allowed_inbound_cidrs : can(cidrhost(cidr, 0))]) && length(var.allowed_inbound_cidrs) <= 100
    error_message = "Provide at most 100 valid CIDRs."
  }
}

variable "log_retention_days" {
  description = "Log Analytics and workspace-based Application Insights retention."
  type        = number
  default     = 30
  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.log_retention_days)
    error_message = "Choose a supported retention period: 30, 60, 90, 120, 180, 270, 365, 550 or 730."
  }
}

variable "alert_email_addresses" {
  description = "Email recipients for actionable app alerts; empty still creates alerts but without notification actions."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to managed resources."
  type        = map(string)
  default     = {}
}
