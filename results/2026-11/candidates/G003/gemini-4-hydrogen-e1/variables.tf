variable "service_name" {
  description = "Short, DNS-safe name of the service (used as the base for Azure resource names)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-32 lowercase alphanumeric characters or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g., dev, staging, prod)."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,12}$", var.environment))
    error_message = "environment must be 1-12 lowercase alphanumeric characters or hyphens."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed."
  type        = string
}

variable "resource_group_name" {
  description = "Optional resource group name. Defaults to rg-<service_name>-<environment>."
  type        = string
  default     = null
}

variable "create_resource_group" {
  description = "Whether the module should create the resource group."
  type        = bool
  default     = true
}

variable "web_app_name" {
  description = "Optional globally unique Web App name override. Defaults to app-<service_name>-<environment>."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all created resources."
  type        = map(string)
  default     = {}
}

variable "container" {
  description = "Container image and runtime configuration for the HTTP API."
  type = object({
    image                      = string
    registry_url               = optional(string, "https://index.docker.io")
    registry_username          = optional(string, null)
    use_managed_identity       = optional(bool, false)
    managed_identity_client_id = optional(string, null)
    port                       = optional(number, 8080)
    command                    = optional(string, null)
    startup_timeout_seconds    = optional(number, 230)
    storage_mount_enabled      = optional(bool, false)
  })

  validation {
    condition     = var.container.port >= 1 && var.container.port <= 65535
    error_message = "container.port must be between 1 and 65535."
  }

  validation {
    condition     = var.container.startup_timeout_seconds >= 60 && var.container.startup_timeout_seconds <= 1800
    error_message = "container.startup_timeout_seconds must be between 60 and 1800."
  }
}

variable "container_registry_password" {
  description = "Optional password or token for private container registry authentication when not using Managed Identity."
  type        = string
  default     = null
  sensitive   = true
}

variable "capacity" {
  description = "Compute tier, baseline worker count, and autoscaling configuration."
  type = object({
    sku_name             = optional(string, "P1v3")
    min_instances        = optional(number, 2)
    max_instances        = optional(number, 10)
    default_instances    = optional(number, 2)
    autoscale_enabled    = optional(bool, true)
    cpu_scale_out_pct    = optional(number, 70)
    cpu_scale_in_pct     = optional(number, 30)
    memory_scale_out_pct = optional(number, 80)
  })
  default = {}

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances
    error_message = "capacity.min_instances must be >= 1 and capacity.max_instances must be >= min_instances."
  }

  validation {
    condition     = var.capacity.default_instances >= var.capacity.min_instances && var.capacity.default_instances <= var.capacity.max_instances
    error_message = "capacity.default_instances must be between min_instances and max_instances."
  }
}

variable "availability" {
  description = "Zone redundancy, runtime availability, and network ingress/egress configuration."
  type = object({
    zone_redundant                = optional(bool, false)
    always_on                     = optional(bool, true)
    public_network_access_enabled = optional(bool, true)
    vnet_subnet_id                = optional(string, null)
    vnet_route_all_enabled        = optional(bool, true)
    vnet_image_pull_enabled       = optional(bool, false)
    ip_restrictions = optional(list(object({
      name                      = string
      priority                  = number
      action                    = optional(string, "Allow")
      ip_address                = optional(string, null)
      service_tag               = optional(string, null)
      virtual_network_subnet_id = optional(string, null)
    })), [])
  })
  default = {}
}

variable "health" {
  description = "Health probe, warmup, and HTTP protocol settings."
  type = object({
    path                    = optional(string, "/healthz")
    eviction_time_minutes   = optional(number, 5)
    warmup_statuses         = optional(string, "200,204")
    http2_enabled           = optional(bool, true)
    minimum_tls_version     = optional(string, "1.2")
    client_affinity_enabled = optional(bool, false)
    cors_allowed_origins    = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = startswith(var.health.path, "/")
    error_message = "health.path must start with '/'."
  }

  validation {
    condition     = var.health.eviction_time_minutes >= 2 && var.health.eviction_time_minutes <= 10
    error_message = "health.eviction_time_minutes must be between 2 and 10."
  }
}

variable "rollout" {
  description = "Deployment slot and zero-downtime rollout settings."
  type = object({
    staging_slot_enabled     = optional(bool, true)
    staging_slot_name        = optional(string, "staging")
    auto_swap_to_production  = optional(bool, false)
    sticky_app_setting_names = optional(list(string), [])
    staging_app_settings     = optional(map(string), {})
    staging_container_image  = optional(string, null)
  })
  default = {}
}

variable "observability" {
  description = "Log Analytics, Application Insights, diagnostics, and Azure Monitor alerting configuration."
  type = object({
    log_analytics_workspace_id   = optional(string, null)
    log_retention_days           = optional(number, 30)
    app_insights_enabled         = optional(bool, true)
    app_insights_sampling_pct    = optional(number, 100)
    diagnostic_logs_enabled      = optional(bool, true)
    alerts_enabled               = optional(bool, true)
    action_group_ids             = optional(list(string), [])
    http_5xx_threshold           = optional(number, 10)
    response_time_threshold_sec  = optional(number, 2.0)
    health_check_alert_threshold = optional(number, 50)
  })
  default = {}
}

variable "app_settings" {
  description = "Additional application environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "user_assigned_identity_ids" {
  description = "Optional list of User-Assigned Managed Identity resource IDs to attach alongside the System-Assigned identity."
  type        = list(string)
  default     = []
}

variable "key_vault_reference_identity_id" {
  description = "Optional User-Assigned Managed Identity ID used for resolving Key Vault references in app_settings."
  type        = string
  default     = null
}
