# ---------------------------------------------------------------------------
# Identity / placement
# ---------------------------------------------------------------------------
variable "name" {
  description = "Service name. Used as the base for all resource names (web app hostname is <name>.azurewebsites.net, so it must be globally unique)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 chars, lowercase letters, digits and hyphens, not starting/ending with a hyphen."
  }
}

variable "location" {
  description = "Azure region, e.g. \"westeurope\"."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into. When null, a resource group named rg-<name> is created."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Workload
# ---------------------------------------------------------------------------
variable "container_image" {
  description = "Container image and tag, without registry host, e.g. \"myteam/orders-api:1.4.2\"."
  type        = string
}

variable "container_registry_url" {
  description = "Registry URL hosting the image, e.g. \"https://myacr.azurecr.io\" or \"https://index.docker.io\"."
  type        = string
  default     = "https://index.docker.io"

  validation {
    condition     = can(regex("^https://", var.container_registry_url))
    error_message = "container_registry_url must start with https://."
  }
}

variable "container_registry_use_managed_identity" {
  description = "Pull the image using the app's system-assigned identity (for ACR). Grant AcrPull to the identity (output principal_id) or set acr_id to have the module do it."
  type        = bool
  default     = false
}

variable "acr_id" {
  description = "Optional resource ID of an Azure Container Registry. When set, the module grants AcrPull to the app (and staging slot) identities and enables managed-identity pulls."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on for HTTP."
  type        = number
  default     = 8080
}

variable "app_settings" {
  description = "Environment variables for the container. Platform settings managed by the module take precedence."
  type        = map(string)
  default     = {}
}

variable "sensitive_app_settings" {
  description = "Secret environment variables (e.g. connection strings). Prefer Key Vault references: \"@Microsoft.KeyVault(SecretUri=...)\"."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Capacity / availability
# ---------------------------------------------------------------------------
variable "sku_name" {
  description = "App Service plan SKU. Premium v3 (P0v3/P1v3/P2v3/P3v3, P*mv3) is recommended for production; Standard (S1-S3) is the minimum supporting slots and autoscale."
  type        = string
  default     = "P0v3"

  validation {
    condition     = can(regex("^(S[1-3]|P[0-3]v3|P[1-5]mv3|P[1-3]v2|I[1-6]v2)$", var.sku_name))
    error_message = "sku_name must be a Standard, PremiumV2/V3 or IsolatedV2 SKU (staging slots and autoscale require at least Standard)."
  }
}

variable "min_instances" {
  description = "Minimum (and initial) instance count. Use >= 2 for availability; >= 3 if zone_redundant."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 30
    error_message = "min_instances must be between 1 and 30."
  }
}

variable "max_instances" {
  description = "Maximum instance count for autoscaling. Set equal to min_instances to disable autoscale."
  type        = number
  default     = 6

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires a Premium v2/v3 or Isolated SKU, a zone-enabled region and min_instances >= 2. Cannot be changed after creation without replacing the plan."
  type        = bool
  default     = false
}

variable "autoscale_cpu_scale_out_percent" {
  description = "Average CPU percentage over 10 minutes above which an instance is added."
  type        = number
  default     = 70
}

variable "autoscale_cpu_scale_in_percent" {
  description = "Average CPU percentage over 10 minutes below which an instance is removed."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Health / rollouts
# ---------------------------------------------------------------------------
variable "health_check_path" {
  description = "HTTP path App Service probes on each instance; unhealthy instances are removed from the load balancer and replaced. Must return 2xx-3xx when healthy."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_minutes" {
  description = "Minutes an instance may fail health checks before being taken out of rotation (2-10)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10
    error_message = "health_check_eviction_minutes must be between 2 and 10."
  }
}

variable "enable_staging_slot" {
  description = "Create a 'staging' deployment slot for blue/green rollouts: deploy to staging, verify, then swap into production."
  type        = bool
  default     = true
}

variable "staging_container_image" {
  description = "Image for the staging slot. Defaults to container_image. Set to a new tag to stage a release before swapping."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "allowed_ip_cidrs" {
  description = "If non-empty, only these CIDRs may reach the app (all other traffic denied). Empty means public."
  type        = list(string)
  default     = []
}

variable "vnet_integration_subnet_id" {
  description = "Optional subnet ID (delegated to Microsoft.Web/serverFarms) for outbound VNet integration."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------
variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace ID. When null, a workspace is created for this service."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention for the module-created Log Analytics workspace."
  type        = number
  default     = 30
}

variable "alert_action_group_ids" {
  description = "Action group IDs notified by the built-in alerts (5xx rate, health check, response time, CPU). Alerts are created even if empty."
  type        = list(string)
  default     = []
}

variable "alert_http5xx_threshold" {
  description = "Number of HTTP 5xx responses in 5 minutes that triggers an alert."
  type        = number
  default     = 10
}

variable "alert_response_time_seconds" {
  description = "Average response time (seconds) over 5 minutes that triggers an alert."
  type        = number
  default     = 2
}
