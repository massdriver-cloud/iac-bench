# ------------------------------------------------------------------------------
# Variables
#
# Grouped by SRE concern: identity, capacity, availability, health, rollouts,
# observability. Where possible, defaults encode team policy so SREs only need
# to set the bits that differ per service.
# ------------------------------------------------------------------------------

# --- Identity & target -------------------------------------------------------

variable "name" {
  description = "Name of the service. Must be globally unique after combining with the resource group (App Service hostnames are global)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,58}[a-z0-9]$", var.name))
    error_message = "name must be lowercase alphanumerics/hyphens, 2-60 chars, no leading/trailing hyphen."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region for the App Service."
  type        = string
}

variable "environment" {
  description = "Environment tag (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}

# --- Capacity ----------------------------------------------------------------

variable "app_service_plan_sku_name" {
  description = "SKU name for the App Service Plan (capacity). e.g. P1v3, P2v3, P3v3. Premium/Isolated v2/v3 required for zone redundancy + slots."
  type        = string
  default     = "P1v3"

  validation {
    condition     = can(regex("^[PIM][0-9]+v[23]$", var.app_service_plan_sku_name))
    error_message = "sku_name must be a Premium/Isolated v2/v3 SKU (needed for zone redundancy + slots)."
  }
}

variable "worker_count" {
  description = "Number of workers (instances) in the App Service Plan. Set to >= 3 to enable zone redundancy (supported on Premium/Isolated SKUs)."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 2
    error_message = "worker_count must be >= 2 for a minimum viable availability posture."
  }
}

# Autoscale (capacity scaling out-of-band). SREs provide thresholds in plain
# terms; the module renders them into Azure Monitor autoscale settings.
variable "autoscale" {
  description = "Optional autoscale configuration. If null, no autoscale settings are created."
  type = object({
    min_capacity     = optional(number, 2)
    max_capacity     = optional(number, 10)
    default_capacity = optional(number, 2)
    cpu_target       = optional(number, 70) # % CPU average to scale on
    memory_target    = optional(number, 75) # % memory average to scale on
  })
  default = null
}

# --- Workload (containers) ---------------------------------------------------

variable "docker_image" {
  description = "Full container image reference, e.g. acr.azurecr.io/service:tag."
  type        = string
}

variable "docker_registry_url" {
  description = "Registry URL, e.g. https://acr.azurecr.io."
  type        = string
}

variable "docker_registry_username" {
  description = "Username for the container registry."
  type        = string
  sensitive   = true
  default     = null
}

variable "docker_registry_password" {
  description = "Password for the container registry."
  type        = string
  sensitive   = true
  default     = null
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

# --- Availability & health ---------------------------------------------------

variable "always_on" {
  description = "Keep the app always loaded (recommended for APIs)."
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Path the app uses for its health probe. Azure pings this path and pulls unhealthy instances."
  type        = string
  default     = "/healthz"
}

variable "https_only" {
  description = "Force HTTPS on all traffic."
  type        = bool
  default     = true
}

# --- Rollouts ----------------------------------------------------------------

variable "deployment_slot" {
  description = "Create a staging deployment slot and swap it into production if true."
  type        = bool
  default     = true
}

# --- Networking --------------------------------------------------------------

variable "virtual_network_subnet_id" {
  description = "Optional subnet ID to integrate the app with (regional VNet integration)."
  type        = string
  default     = null
}

variable "allowed_ip_ranges" {
  description = "List of CIDR ranges allowed to reach the app (access restriction). Empty means allow all."
  type        = list(string)
  default     = []
}

# --- Observability -----------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID to send diagnostic logs/metrics to."
  type        = string
  default     = null
}

variable "application_insights_connection_string" {
  description = "Application Insights connection string for app-level telemetry."
  type        = string
  sensitive   = true
  default     = null
}