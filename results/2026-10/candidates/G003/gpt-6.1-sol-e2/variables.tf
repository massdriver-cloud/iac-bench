variable "name" {
  description = "Globally unique App Service name; also used as the resource name prefix."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,38}[a-z0-9]$", var.name))
    error_message = "Use 4-40 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region with Linux Premium v3 App Service capacity."
  type        = string
}

variable "container_image" {
  description = "Repository and tag or digest, without registry hostname (for example sre/api@sha256:...). Pin a digest for repeatable releases."
  type        = string
  validation {
    condition     = length(trimspace(var.container_image)) > 0
    error_message = "A container image is required."
  }
}

variable "registry_url" {
  description = "HTTPS registry endpoint. Public images or ACR managed identity are supported; no registry passwords are stored."
  type        = string
  default     = "https://index.docker.io"
  validation {
    condition     = can(regex("^https://[^/]+$", var.registry_url))
    error_message = "Use an HTTPS registry URL without a trailing slash or path."
  }
}

variable "acr_resource_id" {
  description = "Optional existing ACR resource ID. Grants AcrPull to the shared user-assigned identity. Registry must use RBAC permissions, not repository ABAC. Set registry_url to this registry's login server."
  type        = string
  default     = null
}

variable "sku_name" {
  description = "Dedicated Linux Premium v3 worker size; staging shares this capacity."
  type        = string
  default     = "P1v3"
  validation {
    condition     = contains(["P1v3", "P2v3", "P3v3"], var.sku_name)
    error_message = "Choose P1v3, P2v3 or P3v3."
  }
}

variable "capacity" {
  description = "Baseline/minimum, maximum, and default worker counts. Autoscale manages worker_count after creation."
  type = object({
    minimum = number
    maximum = number
    initial = number
  })
  default = { minimum = 2, maximum = 4, initial = 2 }
  validation {
    condition = (
      var.capacity.minimum >= 2 && var.capacity.maximum >= var.capacity.initial &&
      var.capacity.initial >= var.capacity.minimum && var.capacity.maximum <= 30 &&
      floor(var.capacity.minimum) == var.capacity.minimum &&
      floor(var.capacity.maximum) == var.capacity.maximum && floor(var.capacity.initial) == var.capacity.initial
    )
    error_message = "Use integer counts with 2 <= minimum <= initial <= maximum <= 30."
  }
}

variable "zone_redundant" {
  description = "Spread workers across availability zones. Region must support zone-redundant Premium v3; minimum capacity must be at least 3. Changing this may replace the plan."
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Unauthenticated readiness path returning HTTP 200-299 without redirects."
  type        = string
  default     = "/health"
  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "Health check path must begin with /."
  }
}

variable "container_port" {
  description = "HTTP port exposed by the container; TLS terminates at App Service."
  type        = number
  default     = 8080
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "Container port must be an integer between 1 and 65535."
  }
}

variable "app_settings" {
  description = "Shared application settings. Use Key Vault references for secrets and grant the identity access outside this module. Platform-owned settings take precedence. Values are stored in state."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "staging_enabled" {
  description = "Create a warm staging slot. Deploy releases here and explicitly swap after verification."
  type        = bool
  default     = true
}

variable "staging_image" {
  description = "Optional independent candidate image, same registry as production. Null uses container_image."
  type        = string
  default     = null
}

variable "allowed_ipv4_cidrs" {
  description = "Optional IPv4 ingress allowlist, applied to both app and SCM endpoints on both slots. Empty means public ingress. Include operator/CI access when restricting."
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.allowed_ipv4_cidrs) <= 100 && alltrue([for cidr in var.allowed_ipv4_cidrs : can(cidrnetmask(cidr))])
    error_message = "Supply at most 100 valid IPv4 CIDRs."
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention."
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "Retention must be an integer between 30 and 730 days."
  }
}

variable "alert_email_addresses" {
  description = "Optional recipients of unhealthy-worker and HTTP 5xx alerts. Empty disables alert resources."
  type        = set(string)
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to supported resources."
  default     = {}
}
