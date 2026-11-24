variable "name" {
  description = "Globally unique web app DNS label; also used as the prefix for dedicated service resources."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "Use 3-40 lowercase DNS-label characters, starting with a letter."
  }
}
variable "location" {
  description = "Azure region supporting Premium v3 App Service and any selected availability features."
  type        = string
  default     = "eastus"
}
variable "image" {
  description = "Container repository and explicit release tag (relative to registry_url). Use a unique, immutable release tag."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image)) && !endswith(lower(var.image), ":latest")
    error_message = "Specify repository:release, not latest."
  }
}
variable "registry_url" {
  type        = string
  description = "HTTPS container registry endpoint. Anonymous pulls by default."
  default     = "https://index.docker.io"
  validation {
    condition     = can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?$", var.registry_url))
    error_message = "Use an HTTPS registry origin without a path."
  }
}
variable "acr_id" {
  type        = string
  default     = null
  description = "Optional private ACR resource ID matching registry_url. Grants a dedicated pull identity AcrPull (registry RBAC mode)."
}
variable "port" {
  type    = number
  default = 80
  validation {
    condition     = var.port == floor(var.port) && var.port >= 1 && var.port <= 65535
    error_message = "Port must be an integer between 1 and 65535."
  }
}
variable "health_path" {
  type        = string
  default     = "/"
  description = "Unauthenticated readiness path returning HTTP 200 without redirects; used for health checks and swap warm-up."
  validation {
    condition     = startswith(var.health_path, "/")
    error_message = "Use an absolute HTTP path."
  }
}
variable "capacity" {
  description = "Dedicated Premium v3 SKU and worker bounds. Set max equal to min for fixed capacity. Zone redundancy requires regional support."
  type        = object({ sku = optional(string, "P1v3"), min = optional(number, 2), max = optional(number, 4), zone_redundant = optional(bool, false) })
  default     = {}
  nullable    = false
  validation {
    condition     = contains(["P1v3", "P2v3", "P3v3"], var.capacity.sku) && var.capacity.min >= (var.capacity.zone_redundant ? 2 : 1) && var.capacity.max >= var.capacity.min && var.capacity.max <= 30 && floor(var.capacity.min) == var.capacity.min && floor(var.capacity.max) == var.capacity.max
    error_message = "Select P1v3/P2v3/P3v3 and whole worker counts 1 <= min <= max <= 30 (min 2 with zones)."
  }
}
variable "staging_image" {
  description = "Optional release image for a staging slot sharing production capacity. Null disables staging."
  type        = string
  default     = null
  validation {
    condition     = var.staging_image == null ? true : can(regex("^[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.staging_image)) && !endswith(lower(var.staging_image), ":latest")
    error_message = "Use repository:release, not latest."
  }
}
variable "app_settings" {
  description = "Common application configuration. Prefer Key Vault references to literal secrets. Platform-controlled keys take precedence."
  type        = map(string)
  default     = {}
}
variable "action_group_ids" {
  description = "Existing Azure Monitor action groups to notify on production 5xx errors."
  type        = set(string)
  default     = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
