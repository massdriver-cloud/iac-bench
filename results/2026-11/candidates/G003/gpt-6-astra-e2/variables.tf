variable "name" {
  description = "Globally unique production app name; also the prefix for dedicated supporting resources."
  type        = string
  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 40 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "Use 3-40 lowercase letters, numbers or hyphens, starting with a letter and ending with a letter or number."
  }
}

variable "location" {
  description = "Azure region supporting Premium v3 and, when enabled, zone-redundant App Service."
  type        = string
  default     = "westeurope"
}

variable "container_image" {
  description = "Repository and tag or digest, without registry hostname (e.g. team/api@sha256:...). Pin an immutable release for production."
  type        = string
  validation {
    condition     = can(regex("^[^[:space:]]+:[^[:space:]]+$", var.container_image)) && !startswith(var.container_image, "https://")
    error_message = "Provide a repository with an explicit tag or digest, without a URL scheme."
  }
}

variable "registry" {
  description = "Container registry URL. Set acr_resource_id for a private, RBAC-mode Azure Container Registry; isolated managed identities receive AcrPull. Other registries must allow anonymous pulls."
  type = object({
    url             = optional(string, "https://mcr.microsoft.com")
    acr_resource_id = optional(string)
  })
  default = {}
  validation {
    condition     = can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?$", var.registry.url))
    error_message = "Registry URL must be an HTTPS origin with no path or trailing slash."
  }
  validation {
    condition     = var.registry.acr_resource_id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ContainerRegistry/registries/[^/]+$", var.registry.acr_resource_id))
    error_message = "acr_resource_id must be a full Azure Container Registry resource ID."
  }
}

variable "container_port" {
  description = "HTTP port the container listens on (bind to 0.0.0.0). TLS terminates at App Service."
  type        = number
  default     = 8080
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "health_check_path" {
  description = "Unauthenticated readiness path returning HTTP 200-299 only when ready; no redirects. Used for health checks and swap warmup."
  type        = string
  default     = "/health"
  validation {
    condition     = startswith(var.health_check_path, "/") && !can(regex("[[:space:]?#]", var.health_check_path))
    error_message = "Use an absolute URL path without whitespace, query or fragment."
  }
}

variable "sku_name" {
  description = "Dedicated Premium v3 worker size. Capacity is managed independently by autoscale."
  type        = string
  default     = "P1v3"
  validation {
    condition     = contains(["P1v3", "P2v3", "P3v3"], var.sku_name)
    error_message = "Supported sizes are P1v3, P2v3 and P3v3."
  }
}

variable "capacity" {
  description = "Autoscale floor/ceiling. Three zone-balanced workers by default; staging shares this capacity. Disabling zones is an explicit availability tradeoff."
  type = object({
    minimum        = optional(number, 3)
    maximum        = optional(number, 6)
    zone_redundant = optional(bool, true)
  })
  default = {}
  validation {
    condition = (
      var.capacity.minimum >= (var.capacity.zone_redundant ? 3 : 1) &&
      var.capacity.maximum >= var.capacity.minimum && var.capacity.maximum <= 30 &&
      floor(var.capacity.minimum) == var.capacity.minimum && floor(var.capacity.maximum) == var.capacity.maximum
    )
    error_message = "Capacity must be integers: 1 <= minimum <= maximum <= 30, with minimum >= 3 when zone redundancy is enabled."
  }
}

variable "enable_staging_slot" {
  description = "Create an isolated-identity staging slot for manual, health-gated swap deployments."
  type        = bool
  default     = true
}

variable "staging_container_image" {
  description = "Candidate repository:tag or repository@digest. Null initially uses the production image. Track both image inputs after a swap; see README."
  type        = string
  default     = null
  validation {
    condition     = var.staging_container_image == null ? true : can(regex("^[^[:space:]]+:[^[:space:]]+$", var.staging_container_image))
    error_message = "The staging image must include an explicit tag or digest."
  }
}

variable "app_settings" {
  description = "Shared application settings, preferably Key Vault reference strings. Platform-owned settings take precedence. Values are stored in state."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "staging_app_settings" {
  description = "Staging overrides, e.g. non-production dependency endpoints. Make environment-specific keys sticky using sticky_app_setting_names."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "sticky_app_setting_names" {
  description = "Additional setting names that must stay with their slot rather than swap. Environment and telemetry settings are always sticky."
  type        = set(string)
  default     = []
}

variable "ingress_cidrs" {
  description = "Production HTTP allowlist. Empty means a public HTTPS API. This module does not implement application authentication."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.ingress_cidrs : can(cidrhost(cidr, 0))]) && length(var.ingress_cidrs) <= 100
    error_message = "Provide at most 100 valid CIDRs."
  }
}

variable "management_cidrs" {
  description = "Allowlisted operator/CI egress CIDRs for staging HTTP and both SCM endpoints. Empty denies all external access to those endpoints; ARM-based container configuration and swaps still work."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.management_cidrs : can(cidrhost(cidr, 0))]) && length(var.management_cidrs) <= 100
    error_message = "Provide at most 100 valid CIDRs."
  }
}

variable "integration_subnet_id" {
  description = "Optional existing subnet delegated to Microsoft.Web/serverFarms for outbound VNet integration of both slots. Provide at least a /26 and correct DNS, NAT/firewall and registry routes. Does not make inbound HTTP private."
  type        = string
  default     = null
}

variable "alert_email_addresses" {
  description = "Nonempty set of monitored SRE mailbox addresses for operational alerts."
  type        = set(string)
  validation {
    condition     = length(var.alert_email_addresses) > 0 && length(var.alert_email_addresses) <= 10 && alltrue([for email in var.alert_email_addresses : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", email))])
    error_message = "Provide 1-10 valid alert email addresses."
  }
}

variable "tags" {
  description = "Resource tags, such as owner, cost-center and environment."
  type        = map(string)
  default     = {}
}
