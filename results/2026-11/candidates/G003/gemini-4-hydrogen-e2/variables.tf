variable "service_name" {
  description = "Short, DNS-safe name of the web service (e.g. 'orders-api'). Used as the naming prefix for all created resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-40 lowercase alphanumeric characters or hyphens, starting with a letter and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment (e.g. 'prod', 'staging', 'dev')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,16}$", var.environment))
    error_message = "environment must be 2-16 lowercase alphanumeric characters or hyphens."
  }
}

variable "location" {
  description = "Azure region for all resources created by this module (e.g. 'eastus2', 'westeurope')."
  type        = string
}

variable "resource_group_name" {
  description = "Optional name of an existing resource group. When null, the module creates a dedicated resource group for the service."
  type        = string
  default     = null
}

variable "container" {
  description = "Container image and registry configuration for the HTTP API."
  type = object({
    image                      = string
    port                       = optional(number, 8080)
    registry_url               = optional(string)
    registry_username          = optional(string)
    registry_password          = optional(string)
    use_managed_identity       = optional(bool, false)
    managed_identity_client_id = optional(string)
    acr_id                     = optional(string)
    startup_command            = optional(string)
  })

  validation {
    condition     = var.container.port >= 1 && var.container.port <= 65535
    error_message = "container.port must be between 1 and 65535."
  }
}

variable "capacity" {
  description = "Compute sizing and autoscaling policy for the App Service Plan."
  type = object({
    service_plan_id       = optional(string)
    size                  = optional(string, "medium")
    sku_name              = optional(string)
    min_instances         = optional(number, 2)
    max_instances         = optional(number, 5)
    autoscale_enabled     = optional(bool, true)
    scale_out_cpu_percent = optional(number, 70)
    scale_in_cpu_percent  = optional(number, 30)
    per_site_scaling      = optional(bool, false)
  })
  default = {}

  validation {
    condition     = contains(["dev", "small", "medium", "large", "xlarge"], var.capacity.size)
    error_message = "capacity.size must be one of: dev, small, medium, large, xlarge."
  }

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances
    error_message = "capacity.min_instances must be >= 1 and capacity.max_instances must be >= min_instances."
  }

  validation {
    condition     = var.capacity.scale_in_cpu_percent < var.capacity.scale_out_cpu_percent
    error_message = "capacity.scale_in_cpu_percent must be strictly less than capacity.scale_out_cpu_percent."
  }
}

variable "availability" {
  description = "Availability, redundancy, and network ingress/egress posture."
  type = object({
    zone_redundant                = optional(bool, false)
    always_on                     = optional(bool, true)
    public_network_access_enabled = optional(bool, true)
    vnet_subnet_id                = optional(string)
    vnet_route_all_enabled        = optional(bool, true)
    vnet_image_pull_enabled       = optional(bool, false)
    load_balancing_mode           = optional(string, "LeastRequests")
    ip_restriction_default_action = optional(string, "Allow")
    ip_restrictions = optional(list(object({
      name        = string
      priority    = number
      action      = optional(string, "Allow")
      ip_address  = optional(string)
      subnet_id   = optional(string)
      service_tag = optional(string)
    })), [])
  })
  default = {}

  validation {
    condition     = contains(["WeightedRoundRobin", "LeastRequests", "LeastResponseTime", "WeightedTotalTraffic", "RequestHash", "PerSiteRoundRobin"], var.availability.load_balancing_mode)
    error_message = "availability.load_balancing_mode must be a valid App Service load balancing mode."
  }

  validation {
    condition     = contains(["Allow", "Deny"], var.availability.ip_restriction_default_action)
    error_message = "availability.ip_restriction_default_action must be 'Allow' or 'Deny'."
  }
}

variable "health" {
  description = "App Service health probe and automatic instance replacement settings."
  type = object({
    path                 = optional(string, "/healthz")
    eviction_time_in_min = optional(number, 5)
  })
  default = {}

  validation {
    condition     = var.health.eviction_time_in_min >= 2 && var.health.eviction_time_in_min <= 10
    error_message = "health.eviction_time_in_min must be between 2 and 10 minutes."
  }
}

variable "rollout" {
  description = "Deployment slot and zero-downtime rollout settings."
  type = object({
    staging_slot_enabled     = optional(bool, true)
    slot_name                = optional(string, "staging")
    staging_image            = optional(string)
    auto_swap_enabled        = optional(bool, false)
    warmup_ping_path         = optional(string)
    warmup_ping_statuses     = optional(string, "200,204")
    sticky_app_setting_names = optional(list(string), [])
    staging_app_settings     = optional(map(string), {})
  })
  default = {}
}

variable "observability" {
  description = "Logging, Application Insights telemetry, and SRE baseline alerting configuration."
  type = object({
    enabled                                = optional(bool, true)
    log_analytics_workspace_id             = optional(string)
    application_insights_id                = optional(string)
    application_insights_connection_string = optional(string)
    log_retention_days                     = optional(number, 30)
    sampling_percentage                    = optional(number, 100)
    application_log_level                  = optional(string, "Information")
    alerts_enabled                         = optional(bool, true)
    action_group_ids                       = optional(list(string), [])
    alert_emails                           = optional(list(string), [])
    alert_thresholds = optional(object({
      http_5xx_count        = optional(number, 5)
      response_time_seconds = optional(number, 2)
      cpu_percent           = optional(number, 85)
      memory_percent        = optional(number, 85)
    }), {})
  })
  default = {}

  validation {
    condition     = contains(["Off", "Error", "Warning", "Information", "Verbose"], var.observability.application_log_level)
    error_message = "observability.application_log_level must be one of: Off, Error, Warning, Information, Verbose."
  }

  validation {
    condition     = var.observability.log_retention_days >= 30 && var.observability.log_retention_days <= 730
    error_message = "observability.log_retention_days must be between 30 and 730."
  }
}

variable "app_settings" {
  description = "Non-sensitive environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "secret_app_settings" {
  description = "Sensitive environment variables injected into the container (marked sensitive in OpenTofu plans)."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "minimum_tls_version" {
  description = "Minimum TLS version accepted by the App Service."
  type        = string
  default     = "1.2"

  validation {
    condition     = contains(["1.2", "1.3"], var.minimum_tls_version)
    error_message = "minimum_tls_version must be '1.2' or '1.3'."
  }
}

variable "cors" {
  description = "Optional CORS configuration for browser-facing HTTP APIs."
  type = object({
    allowed_origins     = list(string)
    support_credentials = optional(bool, false)
  })
  default = null
}

variable "user_assigned_identity_ids" {
  description = "Optional list of User Assigned Managed Identity resource IDs to attach alongside the System Assigned identity."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to all taggable resources."
  type        = map(string)
  default     = {}
}
