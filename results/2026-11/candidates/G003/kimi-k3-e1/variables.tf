# ---------------------------------------------------------------------------
# Required
# ---------------------------------------------------------------------------

variable "name" {
  description = "Service name. Used as the App Service name (must be globally unique in Azure) and as the prefix for the plan, autoscale, and monitoring resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$", var.name))
    error_message = "name must be 3-60 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  description = "Resource group to deploy the service into."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "image" {
  description = "Container image to run, as repository:tag (e.g. myapp/payments-api:1.4.2). Pulled from registry_url."
  type        = string
}

# ---------------------------------------------------------------------------
# Container source
# ---------------------------------------------------------------------------

variable "registry_url" {
  description = "URL of the container registry to pull from (e.g. https://myregistry.azurecr.io for ACR, https://mcr.microsoft.com or https://index.docker.io for public registries)."
  type        = string
  default     = "https://mcr.microsoft.com"
}

variable "container_registry_id" {
  description = "Resource ID of the Azure Container Registry the image is pulled from. When set, the app's system-assigned managed identity is granted AcrPull and registry authentication uses that identity (no admin credentials)."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on. Sets WEBSITES_PORT so App Service routes traffic correctly."
  type        = number
  default     = 8080
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

variable "sku_name" {
  description = "App Service plan SKU. Zone redundancy requires a Premium (P*) or Isolated (I*) SKU; deployment slots require Standard or higher."
  type        = string
  default     = "P1v3"

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "P1v2", "P2v2", "P3v2",
      "P0v3", "P1v3", "P2v3", "P3v3",
      "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
      "I1", "I2", "I3",
      "I1v2", "I2v2", "I3v2",
    ], var.sku_name)
    error_message = "sku_name must be a supported Linux App Service plan SKU."
  }
}

variable "min_capacity" {
  description = "Minimum (and initial) number of plan instances. Autoscaling never goes below this floor."
  type        = number
  default     = 2

  validation {
    condition     = var.min_capacity >= 1 && var.min_capacity <= 30
    error_message = "min_capacity must be between 1 and 30."
  }
}

variable "max_capacity" {
  description = "Maximum number of plan instances autoscaling is allowed to add."
  type        = number
  default     = 10

  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 30
    error_message = "max_capacity must be between 1 and 30."
  }
}

variable "autoscale_enabled" {
  description = "Attach a CPU-based autoscale profile (out above 75% avg, in below 40% avg, 10-minute windows) to the plan."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Availability
# ---------------------------------------------------------------------------

variable "zone_redundant" {
  description = "Spread plan instances across availability zones. Requires a Premium/Isolated SKU and min_capacity >= 2."
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "HTTP path App Service polls for liveness. Instances failing the check are evicted from rotation."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "auto_heal_enabled" {
  description = "Automatically recycle the app when it sustains 5xx responses (25 failures within 5 minutes)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "staging_slot_enabled" {
  description = "Create a 'staging' deployment slot mirroring production for slot-swap rollouts. Requires Standard tier or higher."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Retention for the Log Analytics workspace and Application Insights."
  type        = number
  default     = 30

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.log_retention_days)
    error_message = "log_retention_days must be one of 30, 60, 90, 120, 180, 270, 365, 550, 730."
  }
}

# ---------------------------------------------------------------------------
# Networking / misc
# ---------------------------------------------------------------------------

variable "vnet_integration_subnet_id" {
  description = "Subnet ID for regional VNet integration (outbound traffic). Null disables VNet integration."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Additional environment variables for the app. Merged over module-managed settings, so it can override them if needed."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
  default     = {}
}
