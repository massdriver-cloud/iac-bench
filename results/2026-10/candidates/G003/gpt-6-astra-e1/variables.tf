variable "name" {
  description = "Globally unique web app name; also used to name this deployment's dedicated resources."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "Use 3-40 lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region supporting Linux App Service Premium v3 and, if requested, zone redundancy."
  type        = string
}

variable "container_image" {
  description = "Production image repository and immutable tag or digest (for example, team/api:2026.01.15). Registry host is configured separately."
  type        = string
  validation {
    condition     = length(trimspace(var.container_image)) > 0 && !endswith(var.container_image, ":latest") && can(regex("(:[^/]+|@sha256:[a-f0-9]{64})$", var.container_image))
    error_message = "Specify an explicit image tag (not latest) or sha256 digest. Use immutable tags or digests for repeatable rollouts."
  }
}

variable "registry" {
  description = "Registry HTTPS URL. For private ACR, supply its resource ID to grant the shared user-assigned identity AcrPull. No registry passwords are used."
  type = object({
    server_url  = optional(string, "https://index.docker.io")
    resource_id = optional(string)
  })
  default = {}
  validation {
    condition     = startswith(var.registry.server_url, "https://")
    error_message = "The registry server URL must use HTTPS."
  }
}

variable "container_port" {
  description = "HTTP port exposed by the container; TLS terminates at App Service."
  type        = number
  default     = 80
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer from 1 to 65535."
  }
}

variable "startup_command" {
  description = "Optional container startup command override; null uses the image's command."
  type        = string
  default     = null
}

variable "health_check_path" {
  description = "Unauthenticated readiness endpoint returning 200 when ready. Must be fast and check required dependencies. Used for health checks and swap warm-up."
  type        = string
  default     = "/"
  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must begin with /."
  }
}

variable "sku_name" {
  description = "Dedicated Premium v3 Linux plan size. Premium supports autoscale, deployment slots and optional availability zones."
  type        = string
  default     = "P1v3"
  validation {
    condition     = contains(["P1v3", "P2v3", "P3v3"], var.sku_name)
    error_message = "Choose P1v3, P2v3 or P3v3."
  }
}

variable "capacity" {
  description = "Plan instance bounds and CPU thresholds. With autoscale disabled, minimum is the fixed worker count. Staging shares this capacity."
  type = object({
    autoscale_enabled = optional(bool, true)
    minimum           = optional(number, 2)
    maximum           = optional(number, 4)
    scale_out_cpu     = optional(number, 70)
    scale_in_cpu      = optional(number, 30)
  })
  default = {}
  validation {
    condition = (
      var.capacity.minimum >= 1 && var.capacity.maximum <= 30 &&
      var.capacity.minimum <= var.capacity.maximum &&
      floor(var.capacity.minimum) == var.capacity.minimum && floor(var.capacity.maximum) == var.capacity.maximum &&
      var.capacity.scale_in_cpu > 0 && var.capacity.scale_out_cpu < 100 &&
      var.capacity.scale_in_cpu < var.capacity.scale_out_cpu
    )
    error_message = "Capacity must have integer bounds 1 <= minimum <= maximum <= 30 and 0 < scale_in_cpu < scale_out_cpu < 100."
  }
}

variable "zone_redundant" {
  description = "Distribute workers across availability zones; requires a supporting region and at least two minimum workers. Changing this may replace the plan."
  type        = bool
  default     = false
}

variable "staging" {
  description = "Optional warm staging slot. Image defaults to production; independently set it to release a candidate before an explicit external swap."
  type = object({
    enabled         = optional(bool, true)
    container_image = optional(string)
  })
  default = {}
  validation {
    condition = var.staging.container_image == null ? true : (
      !endswith(var.staging.container_image, ":latest") && can(regex("(:[^/]+|@sha256:[a-f0-9]{64})$", var.staging.container_image))
    )
    error_message = "The staging image must have an explicit non-latest tag or sha256 digest."
  }
}

variable "app_settings" {
  description = "Production environment variables. Prefer Key Vault reference strings for secrets. Module-owned runtime/telemetry settings take precedence. All user setting names are slot-sticky."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "staging_app_settings" {
  description = "Staging-only environment overrides on top of app_settings. All user setting names are slot-sticky. Do not allow staging to write to production dependencies."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "allowed_ip_cidrs" {
  description = "Optional inbound IP allowlist, applied to production, staging and SCM. Empty means public access. Not a private endpoint."
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.allowed_ip_cidrs) <= 400 && alltrue([for cidr in var.allowed_ip_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Supply at most 400 valid CIDR ranges."
  }
}

variable "integration_subnet_id" {
  description = "Optional existing subnet delegated to Microsoft.Web/serverFarms for outbound VNet integration of both apps. Must have enough addresses for scale and slot operations."
  type        = string
  default     = null
}

variable "vnet_route_all_enabled" {
  description = "Route all outbound traffic through the integration subnet when configured. The caller must provide working DNS, routing and registry/telemetry access."
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "Email recipients for the action group. Empty creates alerts without notifications; wire recipients before going live."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for address in var.alert_email_addresses : can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", address))])
    error_message = "Supply valid email addresses."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention in days (30-730)."
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "Log retention must be an integer from 30 to 730 days."
  }
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = map(string)
  default     = {}
}
