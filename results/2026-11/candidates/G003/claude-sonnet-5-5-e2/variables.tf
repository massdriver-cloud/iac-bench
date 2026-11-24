variable "name" {
  description = "Service name. Used as the base for all resource names (lowercase letters, digits, hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 chars, lowercase alphanumerics and hyphens, starting and ending with an alphanumeric."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource group name. If null, a group named rg-<name> is created."
  type        = string
  default     = null
}

variable "create_resource_group" {
  description = "Create the resource group. Set false to deploy into an existing group named by resource_group_name."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment label (e.g. prod, staging, dev). Applied as a tag."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Extra tags applied to all resources."
  type        = map(string)
  default     = {}
}

# ---------- Container ----------

variable "container_image" {
  description = "Container image name including repository path, without registry host, e.g. 'team/api'."
  type        = string
}

variable "container_image_tag" {
  description = "Container image tag. Prefer immutable tags (version or digest-based) over 'latest'."
  type        = string
  default     = "latest"
}

variable "container_registry_url" {
  description = "Registry URL, e.g. https://myacr.azurecr.io."
  type        = string
  default     = "https://mcr.microsoft.com"
}

variable "acr_resource_id" {
  description = "Optional Azure Container Registry resource ID. If set, the app's managed identity is granted AcrPull and pulls via managed identity (no registry passwords)."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "app_settings" {
  description = "Application settings (environment variables) for the container."
  type        = map(string)
  default     = {}
}

# ---------- Capacity ----------

variable "sku_name" {
  description = "App Service plan SKU. Premium v3 (P*v3) by default: supports zone redundancy, slots and autoscale."
  type        = string
  default     = "P1v3"

  validation {
    condition     = can(regex("^(P[0-9]v[2-3]|P[0-9]mv3|I[0-9]v2|S[1-3])$", var.sku_name))
    error_message = "sku_name must be a Standard (S1-S3), Premium v2/v3 or Isolated v2 SKU; Free/Basic lack slots, autoscale and SLA features."
  }
}

variable "min_instances" {
  description = "Minimum instance count (autoscale floor, and the baseline count). Keep >= 2 for availability."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1
    error_message = "min_instances must be at least 1."
  }
}

variable "max_instances" {
  description = "Maximum instance count for autoscale."
  type        = number
  default     = 6

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires a Premium v2/v3 SKU, a zone-enabled region and min_instances >= 2."
  type        = bool
  default     = true
}

variable "autoscale_cpu_scale_out_threshold" {
  description = "Average plan CPU % above which to add an instance."
  type        = number
  default     = 70
}

variable "autoscale_cpu_scale_in_threshold" {
  description = "Average plan CPU % below which to remove an instance."
  type        = number
  default     = 30
}

# ---------- Health & rollout ----------

variable "health_check_path" {
  description = "HTTP path probed by App Service; unhealthy instances are removed from rotation."
  type        = string
  default     = "/healthz"
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may fail health checks before being replaced (2-10)."
  type        = number
  default     = 5
}

variable "enable_staging_slot" {
  description = "Create a 'staging' deployment slot for warm-up and swap-based rollouts."
  type        = bool
  default     = true
}

# ---------- Networking & security ----------

variable "subnet_id" {
  description = "Optional subnet ID (delegated to Microsoft.Web/serverFarms) for regional VNet integration."
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = "Allow public network access to the app."
  type        = bool
  default     = true
}

variable "ip_restriction_allowed_cidrs" {
  description = "If non-empty, only these CIDRs may reach the app (others denied). Empty means no IP restriction."
  type        = list(string)
  default     = []
}

# ---------- Observability ----------

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

variable "alert_email_addresses" {
  description = "Email addresses notified by alerts. If empty, alerts are still created but have no notification target."
  type        = list(string)
  default     = []
}

variable "alert_http_5xx_threshold" {
  description = "Alert if 5xx responses in a 5-minute window exceed this count."
  type        = number
  default     = 10
}

variable "alert_response_time_seconds" {
  description = "Alert if average response time over 5 minutes exceeds this many seconds."
  type        = number
  default     = 2
}
