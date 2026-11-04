# ---------------------------------------------------------------------------
# Standard App Service module for the SRE team.
#
# The SREs interact with a small, semantic surface: capacity, availability,
# health, rollouts and observability. All App Service internals that a
# production HTTP API should have are decided here and applied by default.
# ---------------------------------------------------------------------------

variable "name" {
  description = "Service name. Used as the base for every derived resource name. Lowercase, alphanumeric and hyphens only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,40}[a-z0-9]$", var.name))
    error_message = "name must be 4-42 chars, lowercase alphanumeric with optional inner hyphens."
  }
}

variable "environment" {
  description = "Deployment environment tag (e.g. dev, stg, prd). Influences default capacity and slot behaviour."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "environment must be one of: dev, stg, prd."
  }
}

variable "location" {
  description = "Azure region for the resource group and all resources."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

# ---- Capacity ---------------------------------------------------------------

variable "sku" {
  description = "App Service Plan SKU."
  type = object({
    size     = string # e.g. "P1v3", "B1", "S1"
    tier     = string # e.g. "PremiumV3", "Basic", "Standard"
    capacity = number # worker count
  })
  default = {
    size     = "P1v3"
    tier     = "PremiumV3"
    capacity = 1
  }

  validation {
    condition     = var.sku.capacity >= 1 && var.sku.capacity <= 30
    error_message = "capacity must be between 1 and 30 workers."
  }
}

variable "zone_redundant" {
  description = "Spread App Service Plan across availability zones. Requires a zone-redundant Premium tier."
  type        = bool
  default     = true
}

# ---- Container image ----------------------------------------------------------

variable "image" {
  description = "Container image to run, as registry/{repository}:{tag}."
  type        = string
}

variable "registry" {
  description = "Reference to the container registry. username/password are optional when using the managed identity."
  type = object({
    server_url           = string
    username             = optional(string)
    password             = optional(string)
    use_managed_identity = optional(bool, true)
  })

  validation {
    condition     = var.registry.use_managed_identity || (var.registry.username != null && var.registry.password != null)
    error_message = "Either use_managed_identity or both username and password must be set for the registry."
  }
}

variable "port" {
  description = "Port the container listens on (the WEBSITES_PORT app setting)."
  type        = number
  default     = 8080
}

# ---- Availability & health ----------------------------------------------------

variable "health_check_path" {
  description = "Path the App Service should poll for health. Disable by setting to empty string."
  type        = string
  default     = "/healthz"
}

variable "always_on" {
  description = "Keep the app loaded. Strongly recommended for HTTP APIs."
  type        = bool
  default     = true
}

variable "app_settings" {
  description = "Extra application settings merged on top of the standard ones. Sensitive values go in app_settings_sensitive."
  type        = map(string)
  default     = {}
}

variable "app_settings_sensitive" {
  description = "Sensitive application settings (connection strings, secrets)."
  type        = map(string)
  default     = {}
}

# ---- Diagnostics --------------------------------------------------------------

variable "ip_restrictions" {
  description = "Allow-list for inbound traffic. Empty means unrestricted."
  type = list(object({
    name     = string
    priority = number
    ip       = string # CIDR
    action   = optional(string, "Allow")
  }))
  default = []
}