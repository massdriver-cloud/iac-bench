variable "service_name" {
  description = "Short logical name of the service (lowercase alphanumeric and hyphens). Used to derive resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-40 characters, lowercase letters, digits, and hyphens, starting and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment identifier (e.g., dev, staging, prod)."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,16}$", var.environment))
    error_message = "environment must be 2-16 lowercase alphanumeric characters or hyphens."
  }
}

variable "location" {
  description = "Azure region where the service and supporting resources are deployed."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Name of an existing Resource Group to deploy into. When null, a dedicated Resource Group is created for the service."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all resources alongside standard service/environment tags."
  type        = map(string)
  default     = {}
}

variable "container" {
  description = "Container workload configuration for the HTTP API."
  type = object({
    image_name                   = string
    registry_url                 = optional(string, "https://index.docker.io")
    port                         = optional(number, 8080)
    startup_command              = optional(string)
    use_managed_identity_for_acr = optional(bool, true)
    registry_username            = optional(string)
    registry_password            = optional(string)
  })

  validation {
    condition     = var.container.port >= 1 && var.container.port <= 65535
    error_message = "container.port must be between 1 and 65535."
  }
}

variable "app_settings" {
  description = "Non-secret environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "sticky_app_settings" {
  description = "Names of app_settings or connection_strings that remain pinned to their deployment slot during swaps."
  type = object({
    app_setting_names       = optional(list(string), [])
    connection_string_names = optional(list(string), [])
  })
  default = {}
}

variable "capacity" {
  description = "Compute tier, instance scaling bounds, and autoscale thresholds for the App Service Plan."
  type = object({
    sku_name                 = optional(string, "P1v3")
    min_instances            = optional(number, 2)
    max_instances            = optional(number, 10)
    default_instances        = optional(number, 2)
    enable_autoscale         = optional(bool, true)
    cpu_scale_out_percent    = optional(number, 70)
    cpu_scale_in_percent     = optional(number, 35)
    memory_scale_out_percent = optional(number, 80)
  })
  default = {}

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "P1v2", "P2v2", "P3v2",
      "P0v3", "P1v3", "P2v3", "P3v3",
      "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3"
    ], var.capacity.sku_name)
    error_message = "capacity.sku_name must be a valid Linux App Service Plan SKU (Basic, Standard, Premium v2, or Premium v3)."
  }

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances && var.capacity.default_instances >= var.capacity.min_instances && var.capacity.default_instances <= var.capacity.max_instances
    error_message = "capacity instance counts must satisfy: 1 <= min_instances <= default_instances <= max_instances."
  }
}

variable "availability" {
  description = "Zone redundancy and auto-heal recovery policies."
  type = object({
    zone_balancing_enabled = optional(bool, false)
    always_on              = optional(bool, true)
    http2_enabled          = optional(bool, true)
  })
  default = {}
}

variable "health" {
  description = "HTTP health check endpoint and eviction threshold."
  type = object({
    path                 = optional(string, "/healthz")
    eviction_time_in_min = optional(number, 5)
    warm_up_path         = optional(string)
    warm_up_status_codes = optional(string, "200-299")
  })
  default = {}

  validation {
    condition     = startswith(var.health.path, "/")
    error_message = "health.path must start with '/'."
  }

  validation {
    condition     = var.health.eviction_time_in_min >= 2 && var.health.eviction_time_in_min <= 10
    error_message = "health.eviction_time_in_min must be between 2 and 10 minutes."
  }
}

variable "rollout" {
  description = "Staging slot and blue/green rollout settings."
  type = object({
    enable_staging_slot = optional(bool, true)
    staging_image_name  = optional(string)
    auto_swap_enabled   = optional(bool, false)
    staging_traffic_pct = optional(number, 0)
  })
  default = {}

  validation {
    condition     = var.rollout.staging_traffic_pct >= 0 && var.rollout.staging_traffic_pct <= 100
    error_message = "rollout.staging_traffic_pct must be between 0 and 100."
  }
}

variable "networking" {
  description = "VNet integration, inbound access restrictions, and CORS policies."
  type = object({
    integration_subnet_id         = optional(string)
    vnet_route_all_enabled        = optional(bool, true)
    public_network_access_enabled = optional(bool, true)
    scm_use_main_ip_restriction   = optional(bool, true)
    cors_allowed_origins          = optional(list(string), [])
    cors_support_credentials      = optional(bool, false)
    ip_restrictions = optional(list(object({
      name                      = string
      priority                  = number
      action                    = optional(string, "Allow")
      ip_address                = optional(string)
      virtual_network_subnet_id = optional(string)
      service_tag               = optional(string)
    })), [])
  })
  default = {}
}

variable "observability" {
  description = "Log Analytics, Application Insights, diagnostics, and metric alerting configuration."
  type = object({
    log_analytics_workspace_id  = optional(string)
    retention_in_days           = optional(number, 30)
    daily_quota_gb              = optional(number, -1)
    enable_application_insights = optional(bool, true)
    sampling_percentage         = optional(number, 100)
    http_logs_retention_days    = optional(number, 7)
    http_logs_retention_mb      = optional(number, 100)
    enable_default_alerts       = optional(bool, true)
    alert_action_group_ids      = optional(list(string), [])
    http_5xx_threshold          = optional(number, 10)
    response_time_threshold_sec = optional(number, 3)
    health_check_min_percent    = optional(number, 90)
  })
  default = {}

  validation {
    condition     = var.observability.retention_in_days >= 30 && var.observability.retention_in_days <= 730
    error_message = "observability.retention_in_days must be between 30 and 730."
  }
}

variable "identity" {
  description = "Managed identity configuration for the service."
  type = object({
    enable_system_assigned = optional(bool, true)
    user_assigned_ids      = optional(list(string), [])
  })
  default = {}
}
