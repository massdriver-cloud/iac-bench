# ---------------------------------------------------------------------------
# Required: identity of the service being deployed
# ---------------------------------------------------------------------------

variable "service_name" {
  description = "Short, DNS-safe name of the service (e.g. 'orders-api'). Used to name all resources: rg-<name>, plan-<name>, app-<name>, etc. The resulting app name must be globally unique in Azure."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-40 chars, lowercase letters/digits/hyphens, starting and ending with a letter or digit."
  }
}

variable "container_image" {
  description = "Full container image reference to run, e.g. 'myacr.azurecr.io/orders-api:1.4.2' or 'mcr.microsoft.com/azuredocs/aci-helloworld:latest'. Bare Docker Hub references (e.g. 'nginx:latest') are also accepted. For private ACR images, also set acr_resource_id so the app pulls with its managed identity."
  type        = string
}

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "Tags applied to every resource. 'service' is added automatically."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Capacity & availability
# ---------------------------------------------------------------------------

variable "sku_name" {
  description = "App Service Plan SKU. The standard is P1v3 (Premium v3). B* is acceptable for non-production; F1/D1 disable always-on; deployment slots require S*, P* or I*."
  type        = string
  default     = "P1v3"
}

variable "worker_count" {
  description = "Number of plan instances. The standard is 3 so a single-instance failure or platform update never takes the service down. Use 1 only for non-production."
  type        = number
  default     = 3

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 30
    error_message = "worker_count must be between 1 and 30."
  }
}

variable "zone_redundant" {
  description = "Spread plan instances across availability zones. Requires a Premium v2/v3 SKU (P*v2/P*v3) and worker_count >= 3; the plan will fail fast otherwise."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Container runtime
# ---------------------------------------------------------------------------

variable "container_port" {
  description = "Port the container listens on. Exported as WEBSITES_PORT so App Service routes traffic correctly."
  type        = number
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port (1-65535)."
  }
}

variable "acr_resource_id" {
  description = "Resource ID of the Azure Container Registry hosting the image, if private. Grants the app (and staging slot) AcrPull via managed identity - no registry passwords are stored."
  type        = string
  default     = null
}

variable "extra_app_settings" {
  description = "Additional application settings (environment variables) for the app and staging slot. For secrets, prefer Key Vault references (@Microsoft.KeyVault(...))."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

variable "health_check_path" {
  description = "HTTP path App Service probes on every instance (e.g. '/healthz'). Unhealthy instances are evicted after 5 minutes. Set to '' to disable probing (not recommended)."
  type        = string
  default     = "/health"
}

variable "always_on" {
  description = "Keep the app warm (no idle unload). Ignored on F1/D1 SKUs, which do not support it."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "staging_slot_enabled" {
  description = "Create a 'staging' deployment slot for warm-up and validation before swap. Requires an S*, P* or I* SKU; silently skipped on lower tiers. The slot mirrors the production configuration."
  type        = bool
  default     = true
}

variable "auto_swap_enabled" {
  description = "Automatically swap the staging slot into production after a successful deployment/warm-up. Only effective when the staging slot exists. Leave false for manual, gated swaps."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "enable_app_insights" {
  description = "Create workspace-based Application Insights and inject APPLICATIONINSIGHTS_CONNECTION_STRING into the app so SDK/auto-instrumentation can report telemetry."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Interactive retention (days) for the service's Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}
