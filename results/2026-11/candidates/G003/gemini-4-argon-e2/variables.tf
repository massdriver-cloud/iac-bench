variable "name" {
  description = "Workload or service name used as the base prefix for all resources (e.g., 'payments-api')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}[a-z0-9]$", var.name))
    error_message = "Name must be 3-42 characters of lowercase letters, numbers, and hyphens, starting and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment identifier (e.g., 'prod', 'staging', 'dev')."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.environment))
    error_message = "Environment must be 2-12 lowercase alphanumeric characters."
  }
}

variable "location" {
  description = "Azure region where the service and its supporting infrastructure are deployed."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Existing resource group name. If null, a dedicated resource group is created for the service."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all created Azure resources."
  type        = map(string)
  default     = {}
}

variable "container" {
  description = "Container image and runtime configuration for the HTTP API service."
  type = object({
    image_name             = string
    image_tag              = optional(string, "latest")
    registry_url           = optional(string, "https://index.docker.io")
    registry_use_msi       = optional(bool, false)
    registry_msi_client_id = optional(string)
    registry_username      = optional(string)
    registry_password      = optional(string)
    port                   = optional(number, 8080)
    startup_command        = optional(string)
  })
}

variable "capacity" {
  description = "Compute tier, instance sizing, zone redundancy, and CPU/Memory/HTTP queue autoscale rules."
  type = object({
    sku_name                   = optional(string, "P1v3")
    zone_balancing_enabled     = optional(bool, true)
    autoscale_enabled          = optional(bool, true)
    min_instances              = optional(number, 3)
    max_instances              = optional(number, 10)
    default_instances          = optional(number, 3)
    scale_out_cpu_threshold    = optional(number, 70)
    scale_in_cpu_threshold     = optional(number, 35)
    scale_out_memory_threshold = optional(number, 80)
    scale_out_http_queue_depth = optional(number, 100)
  })
  default = {}

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances && var.capacity.default_instances >= var.capacity.min_instances && var.capacity.default_instances <= var.capacity.max_instances
    error_message = "Capacity instances must satisfy: 1 <= min_instances <= default_instances <= max_instances."
  }

  validation {
    condition     = !var.capacity.zone_balancing_enabled || var.capacity.min_instances >= 3
    error_message = "Zone balancing requires at least 3 minimum instances (min_instances >= 3) on Premium v2/v3 plans."
  }
}

variable "health" {
  description = "Application health probing, auto-heal policies, and runtime liveness configuration."
  type = object({
    path                       = optional(string, "/healthz")
    eviction_time_in_min       = optional(number, 5)
    always_on                  = optional(bool, true)
    http2_enabled              = optional(bool, true)
    client_affinity_enabled    = optional(bool, false)
    container_start_time_limit = optional(number, 230)
  })
  default = {}

  validation {
    condition     = startswith(var.health.path, "/")
    error_message = "Health check path must start with '/'."
  }

  validation {
    condition     = var.health.eviction_time_in_min >= 2 && var.health.eviction_time_in_min <= 10
    error_message = "Health check eviction_time_in_min must be between 2 and 10 minutes."
  }
}

variable "rollout" {
  description = "Safe rollout, staging slot, warmup probing, and auto-swap configuration."
  type = object({
    staging_slot_enabled     = optional(bool, true)
    auto_swap_enabled        = optional(bool, false)
    staging_image_tag        = optional(string)
    warmup_init_paths        = optional(list(string), ["/healthz"])
    warmup_status_codes      = optional(list(string), ["200"])
    slot_sticky_app_settings = optional(list(string), [])
  })
  default = {}
}

variable "observability" {
  description = "Logs, metrics, distributed tracing (Application Insights), diagnostic shipping, and SLO alerts."
  type = object({
    log_analytics_workspace_id             = optional(string)
    application_insights_id                = optional(string)
    application_insights_connection_string = optional(string)
    retention_in_days                      = optional(number, 30)
    daily_quota_gb                         = optional(number, 5)
    sampling_percentage                    = optional(number, 100)
    http_logs_retention_days               = optional(number, 7)
    http_logs_retention_mb                 = optional(number, 100)
    alerts_enabled                         = optional(bool, true)
    alert_action_group_ids                 = optional(list(string), [])
    alert_5xx_threshold                    = optional(number, 10)
    alert_latency_p95_ms_threshold         = optional(number, 1500)
    alert_health_threshold_percent         = optional(number, 80)
    alert_cpu_threshold_percent            = optional(number, 85)
    alert_memory_threshold_percent         = optional(number, 85)
  })
  default = {}
}

variable "network" {
  description = "Network isolation, VNet integration, and ingress access restrictions."
  type = object({
    public_network_access_enabled     = optional(bool, true)
    virtual_network_subnet_id         = optional(string)
    vnet_route_all_enabled            = optional(bool, true)
    vnet_image_pull_enabled           = optional(bool, false)
    ip_restriction_default_action     = optional(string, "Allow")
    scm_ip_restriction_default_action = optional(string, "Deny")
    scm_use_main_ip_restriction       = optional(bool, false)
    allowed_cidrs                     = optional(list(string), [])
    allowed_subnet_ids                = optional(list(string), [])
    allowed_service_tags              = optional(list(string), [])
    cors_allowed_origins              = optional(list(string), [])
    cors_support_credentials          = optional(bool, false)
  })
  default = {}
}

variable "app_settings" {
  description = "Additional environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "key_vault_reference_identity_id" {
  description = "Optional User Assigned Managed Identity resource ID used to resolve Key Vault references in app_settings."
  type        = string
  default     = null
}

variable "user_assigned_identity_ids" {
  description = "Optional list of User Assigned Managed Identity resource IDs to attach alongside the System Assigned Identity."
  type        = list(string)
  default     = []
}
