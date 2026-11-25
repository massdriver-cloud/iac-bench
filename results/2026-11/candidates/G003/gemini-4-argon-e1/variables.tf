variable "name" {
  description = "Canonical name of the web service (used as prefix/base for Azure resources)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}[a-z0-9]$", var.name))
    error_message = "Name must be 3-42 characters, lowercase alphanumeric and hyphens, starting and ending with alphanumeric."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g., prod, staging, dev)."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,16}$", var.environment))
    error_message = "Environment must be 2-16 lowercase alphanumeric characters or hyphens."
  }
}

variable "location" {
  description = "Azure region for all deployed resources."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Name of an existing Resource Group to deploy into. When create_resource_group is true, a new Resource Group with this name (or a default derived name) is created."
  type        = string
  default     = null
}

variable "create_resource_group" {
  description = "Whether to create a new Azure Resource Group for this service."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all supported resources."
  type        = map(string)
  default     = {}
}

variable "container" {
  description = "Container image and runtime configuration for the HTTP service."
  type = object({
    image                         = string
    registry_url                  = optional(string, "https://index.docker.io")
    registry_use_managed_identity = optional(bool, false)
    registry_username             = optional(string)
    registry_password             = optional(string)
    port                          = optional(number, 8080)
    startup_command               = optional(string)
    mount_storage = optional(list(object({
      name         = string
      account_name = string
      share_name   = string
      access_key   = string
      mount_path   = string
      type         = optional(string, "AzureFiles")
    })), [])
  })

  validation {
    condition     = length(trimspace(var.container.image)) > 0
    error_message = "container.image must be a non-empty image reference (e.g., 'nginx:1.25-alpine' or 'myacr.azurecr.io/api:v1.2.3')."
  }

  validation {
    condition     = var.container.port >= 1 && var.container.port <= 65535
    error_message = "container.port must be a valid TCP port between 1 and 65535."
  }
}

variable "app_settings" {
  description = "Non-secret application environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "sticky_app_settings" {
  description = "List of app setting keys that remain pinned to their slot during a blue/green swap."
  type        = list(string)
  default     = []
}

variable "connection_strings" {
  description = "Database or service connection strings exposed to the application."
  type = list(object({
    name  = string
    type  = optional(string, "Custom")
    value = string
  }))
  default   = []
  sensitive = true
}

variable "capacity" {
  description = "Service capacity, compute SKU tier, and horizontal autoscale thresholds."
  type = object({
    sku_name                 = optional(string, "P1v3")
    min_instances            = optional(number, 2)
    max_instances            = optional(number, 10)
    default_instances        = optional(number, 2)
    autoscale_enabled        = optional(bool, true)
    cpu_scale_out_percent    = optional(number, 70)
    cpu_scale_in_percent     = optional(number, 30)
    memory_scale_out_percent = optional(number, 80)
    http_queue_scale_out     = optional(number, 100)
    scale_out_cooldown_mins  = optional(number, 5)
    scale_in_cooldown_mins   = optional(number, 10)
  })
  default = {}

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances && var.capacity.default_instances >= var.capacity.min_instances && var.capacity.default_instances <= var.capacity.max_instances
    error_message = "capacity instance counts must satisfy: 1 <= min_instances <= default_instances <= max_instances."
  }

  validation {
    condition     = contains(["B1", "B2", "B3", "S1", "S2", "S3", "P1v2", "P2v2", "P3v2", "P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3"], var.capacity.sku_name)
    error_message = "capacity.sku_name must be a valid Linux App Service Plan SKU (e.g., P0v3, P1v3, P2v3, P3v3, S1, B1)."
  }
}

variable "availability" {
  description = "High availability, zone redundancy, and runtime resiliency controls."
  type = object({
    zone_balancing_enabled = optional(bool, true)
    always_on              = optional(bool, true)
    http2_enabled          = optional(bool, true)
    auto_heal_enabled      = optional(bool, true)
    auto_heal_status_codes = optional(object({
      status_code_range = optional(string, "500-599")
      count             = optional(number, 50)
      interval          = optional(string, "00:02:00")
    }), {})
    auto_heal_slow_requests = optional(object({
      time_taken = optional(string, "00:00:30")
      count      = optional(number, 25)
      interval   = optional(string, "00:02:00")
    }), {})
  })
  default = {}
}

variable "health" {
  description = "HTTP health probe path and unhealthy instance eviction timing."
  type = object({
    path                      = optional(string, "/healthz")
    eviction_time_in_min      = optional(number, 5)
    probe_alert_enabled       = optional(bool, true)
    healthy_threshold_percent = optional(number, 90)
  })
  default = {}

  validation {
    condition     = startswith(var.health.path, "/")
    error_message = "health.path must start with '/'."
  }

  validation {
    condition     = var.health.eviction_time_in_min >= 2 && var.health.eviction_time_in_min <= 10
    error_message = "health.eviction_time_in_min must be between 2 and 10 minutes per Azure App Service limits."
  }
}

variable "rollout" {
  description = "Staging slot, traffic routing, and safe deployment rollout settings."
  type = object({
    staging_slot_enabled    = optional(bool, true)
    staging_traffic_percent = optional(number, 0)
    auto_swap_enabled       = optional(bool, false)
    warm_up_init_path       = optional(string, "/healthz")
    warm_up_status_codes    = optional(string, "200-299")
    staging_image_override  = optional(string)
    staging_app_settings    = optional(map(string), {})
  })
  default = {}

  validation {
    condition     = var.rollout.staging_traffic_percent >= 0 && var.rollout.staging_traffic_percent <= 100
    error_message = "rollout.staging_traffic_percent must be between 0 and 100."
  }
}

variable "observability" {
  description = "Telemetry, log analytics, application insights, diagnostic logs, and SRE alerting configuration."
  type = object({
    log_analytics_workspace_id   = optional(string)
    retention_in_days            = optional(number, 30)
    application_insights_enabled = optional(bool, true)
    sampling_percentage          = optional(number, 100)
    http_logs_retention_days     = optional(number, 7)
    http_logs_retention_mb       = optional(number, 100)
    detailed_error_messages      = optional(bool, true)
    failed_request_tracing       = optional(bool, true)
    alerts_enabled               = optional(bool, true)
    action_group_ids             = optional(list(string), [])
    alert_emails                 = optional(list(string), [])
    http_5xx_threshold           = optional(number, 10)
    response_time_threshold_sec  = optional(number, 2.5)
    cpu_alert_threshold_percent  = optional(number, 85)
    memory_alert_threshold_pct   = optional(number, 85)
  })
  default = {}

  validation {
    condition     = var.observability.retention_in_days >= 30 && var.observability.retention_in_days <= 730
    error_message = "observability.retention_in_days must be between 30 and 730 days."
  }
}

variable "network" {
  description = "Network integration, ingress restrictions, CORS, and TLS security posture."
  type = object({
    vnet_integration_subnet_id    = optional(string)
    vnet_route_all_enabled        = optional(bool, true)
    public_network_access_enabled = optional(bool, true)
    minimum_tls_version           = optional(string, "1.2")
    client_certificate_enabled    = optional(bool, false)
    client_certificate_mode       = optional(string, "Required")
    ip_restrictions = optional(list(object({
      name                      = string
      priority                  = number
      action                    = optional(string, "Allow")
      ip_address                = optional(string)
      virtual_network_subnet_id = optional(string)
      service_tag               = optional(string)
    })), [])
    scm_use_main_ip_restriction = optional(bool, true)
    cors = optional(object({
      allowed_origins     = list(string)
      support_credentials = optional(bool, false)
    }))
  })
  default = {}
}

variable "identity" {
  description = "Managed Identity configuration for the service (SystemAssigned is always enabled; optional UserAssigned IDs can be attached)."
  type = object({
    user_assigned_identity_ids      = optional(list(string), [])
    key_vault_reference_identity_id = optional(string)
  })
  default = {}
}
