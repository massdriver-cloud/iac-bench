############################################
# Identity of the service
############################################

variable "name" {
  description = "Short service name (lowercase letters, digits, hyphens). Used to derive all resource names; the web app hostname becomes <name>-<environment>.azurewebsites.net."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 chars, lowercase letters/digits/hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment label (e.g. dev, staging, prod). Part of resource names and tags."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.environment))
    error_message = "environment must be 2-8 lowercase alphanumeric characters."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into. If null, the module creates rg-<name>-<environment>."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}

############################################
# Workload
############################################

variable "container_image" {
  description = "Initial container image as <repository>:<tag> (e.g. 'myteam/orders-api:1.4.2'), relative to container_registry_url. Used at creation time for both production and staging slot; subsequent rollouts are done by deploying to the staging slot and swapping, so later changes to this value are intentionally ignored by Terraform."
  type        = string

  validation {
    condition     = can(regex("^[^\\s:]+:[^\\s:]+$", var.container_image))
    error_message = "container_image must be '<repository>:<tag>' with an explicit tag (no 'latest'-by-default images)."
  }
}

variable "container_registry_url" {
  description = "Registry URL including scheme, e.g. https://myregistry.azurecr.io or https://index.docker.io."
  type        = string
  default     = "https://mcr.microsoft.com"

  validation {
    condition     = can(regex("^https://", var.container_registry_url))
    error_message = "container_registry_url must start with https://."
  }
}

variable "acr_id" {
  description = "Resource ID of an Azure Container Registry to pull from. When set, the app (and staging slot) pull using their system-assigned managed identity and are granted AcrPull on it. Leave null for public registries."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on for HTTP."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port > 0 && var.container_port < 65536
    error_message = "container_port must be a valid TCP port."
  }
}

variable "app_settings" {
  description = "Application environment variables. For secrets use Key Vault references (@Microsoft.KeyVault(SecretUri=...)) and grant the app identity access; do not put raw secrets here."
  type        = map(string)
  default     = {}
}

variable "slot_sticky_app_settings" {
  description = "Names of app settings that stay with the slot on swap (e.g. environment-specific endpoints)."
  type        = list(string)
  default     = []
}

############################################
# Capacity & availability
############################################

variable "sku_name" {
  description = "App Service plan SKU. Restricted to tiers that support autoscale, deployment slots and (for v3) zone redundancy."
  type        = string
  default     = "P1v3"

  validation {
    condition     = contains(["S1", "S2", "S3", "P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3"], var.sku_name)
    error_message = "sku_name must be a Standard or Premium v3 SKU (S1-S3, P0v3-P3v3, P1mv3-P5mv3)."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires a Premium v3 SKU, a zone-capable region, and min_instances >= 2. Cannot be changed after creation without replacing the plan."
  type        = bool
  default     = false
}

variable "min_instances" {
  description = "Minimum (and baseline) instance count. 2+ is recommended for production so a single instance restart doesn't cause an outage."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 30
    error_message = "min_instances must be between 1 and 30."
  }
}

variable "max_instances" {
  description = "Maximum instance count autoscale may reach. Set equal to min_instances to disable scaling out."
  type        = number
  default     = 6

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "scale_out_cpu_percent" {
  description = "Average plan CPU % (over 10 minutes) above which one instance is added."
  type        = number
  default     = 70
}

variable "scale_in_cpu_percent" {
  description = "Average plan CPU % (over 10 minutes) below which one instance is removed."
  type        = number
  default     = 30
}

############################################
# Health & rollouts
############################################

variable "health_check_path" {
  description = "HTTP path App Service probes on every instance. Unhealthy instances are removed from the load balancer and replaced. Must return 2xx when the instance can serve traffic."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_minutes" {
  description = "Minutes an instance may fail health checks before it is evicted and replaced (2-10)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10
    error_message = "health_check_eviction_minutes must be between 2 and 10."
  }
}

variable "enable_staging_slot" {
  description = "Create a 'staging' deployment slot for zero-downtime rollouts (deploy to staging, verify, swap)."
  type        = bool
  default     = true
}

############################################
# Observability
############################################

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace ID. If null, the module creates one."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention for the module-created Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "alert_email_addresses" {
  description = "Emails notified by the module's alerts. If empty, alerts still fire (visible in Azure Monitor) but notify nobody."
  type        = list(string)
  default     = []
}

variable "alert_http_5xx_threshold" {
  description = "Alert when the count of HTTP 5xx responses in 5 minutes exceeds this."
  type        = number
  default     = 10
}

variable "alert_response_time_seconds" {
  description = "Alert when average response time over 5 minutes exceeds this many seconds."
  type        = number
  default     = 2
}
