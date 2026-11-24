# ------------------------------------------------------------------------------
# Required Service Identity & Workload Inputs
# ------------------------------------------------------------------------------

variable "service_name" {
  description = "Short, lowercase identifier for the service (e.g. 'orders-api'). Used in resource naming and tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.service_name)) && !endswith(var.service_name, "-")
    error_message = "service_name must be 2-20 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and not end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g. 'prod', 'staging', 'dev', 'qa')."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,7}$", var.environment)) && !endswith(var.environment, "-")
    error_message = "environment must be 2-8 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and not end with a hyphen."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed (e.g. 'eastus2', 'westeurope')."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must be a non-empty Azure region name."
  }
}

variable "container_image" {
  description = "Container image and tag to run (e.g. 'myacr.azurecr.io/orders-api:1.4.2' or 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest')."
  type        = string

  validation {
    condition     = length(trimspace(var.container_image)) > 0 && !can(regex("\\s", var.container_image))
    error_message = "container_image must be a non-empty image reference without whitespace."
  }
}

# ------------------------------------------------------------------------------
# Resource Placement, Naming & Tagging
# ------------------------------------------------------------------------------

variable "create_resource_group" {
  description = "Whether to create a dedicated Resource Group for the service. Set to false and provide resource_group_name to deploy into an existing Resource Group."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Optional explicit Resource Group name. Required when create_resource_group is false; auto-generated when null and create_resource_group is true."
  type        = string
  default     = null

  validation {
    condition     = var.resource_group_name == null || length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name, when specified, must be non-empty."
  }
}

variable "existing_service_plan_id" {
  description = "Optional resource ID of an existing Linux App Service Plan to host the app. When null, a dedicated App Service Plan is created."
  type        = string
  default     = null
}

variable "name_suffix" {
  description = "Optional 2-8 character lowercase alphanumeric suffix for globally unique names. If null, a random 4-character suffix is generated."
  type        = string
  default     = null

  validation {
    condition     = var.name_suffix == null || can(regex("^[a-z0-9]{2,8}$", var.name_suffix))
    error_message = "name_suffix must be 2-8 lowercase alphanumeric characters."
  }
}

variable "tags" {
  description = "Additional tags applied to all created Azure resources."
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Container Runtime & Registry
# ------------------------------------------------------------------------------

variable "container" {
  description = "Container runtime and registry configuration."
  type = object({
    port                           = optional(number)
    registry_url                   = optional(string)
    registry_username              = optional(string)
    use_managed_identity_for_acr   = optional(bool, false)
    acr_id                         = optional(string)
    acr_managed_identity_client_id = optional(string)
    start_command                  = optional(string)
    enable_app_service_storage     = optional(bool, false)
    vnet_image_pull_enabled        = optional(bool, false)
  })
  default = {}

  validation {
    condition     = var.container.port == null || (var.container.port >= 1 && var.container.port <= 65535)
    error_message = "container.port must be between 1 and 65535."
  }

  validation {
    condition     = var.container.registry_url == null || can(regex("^https?://", var.container.registry_url))
    error_message = "container.registry_url must include the scheme (e.g. 'https://myacr.azurecr.io')."
  }
}

variable "container_registry_password" {
  description = "Optional password or token for private container registries when not using ACR Managed Identity."
  type        = string
  default     = null
  sensitive   = true
}

# ------------------------------------------------------------------------------
# Application Configuration & Identity
# ------------------------------------------------------------------------------

variable "app_settings" {
  description = "Non-sensitive environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "secret_app_settings" {
  description = "Sensitive environment variables or Key Vault references (e.g. '@Microsoft.KeyVault(SecretUri=...)') injected into the container."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "sticky_app_settings" {
  description = "Additional app setting names pinned to their respective deployment slot during swaps."
  type        = list(string)
  default     = []
}

variable "user_assigned_identity_ids" {
  description = "Optional list of User-Assigned Managed Identity resource IDs to attach alongside the default System-Assigned Managed Identity."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------
# Capacity (Sizing & Autoscaling)
# ------------------------------------------------------------------------------

variable "capacity" {
  description = "Compute sizing and autoscaling policy for the service."
  type = object({
    size                 = optional(string, "medium")
    sku_name             = optional(string)
    min_instances        = optional(number, 2)
    max_instances        = optional(number, 6)
    default_instances    = optional(number)
    autoscale_enabled    = optional(bool, true)
    cpu_scale_out_pct    = optional(number, 70)
    cpu_scale_in_pct     = optional(number, 30)
    mem_scale_out_pct    = optional(number, 80)
    mem_scale_in_pct     = optional(number, 40)
    http_queue_scale_out = optional(number, 100)
    scale_out_cooldown   = optional(string, "PT5M")
    scale_in_cooldown    = optional(string, "PT10M")
  })
  default = {}

  validation {
    condition     = contains(["dev", "small", "medium", "large", "xlarge"], var.capacity.size)
    error_message = "capacity.size must be one of: dev, small, medium, large, xlarge."
  }

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances && var.capacity.max_instances <= 30
    error_message = "capacity.min_instances must be >= 1, capacity.max_instances must be >= min_instances and <= 30."
  }

  validation {
    condition     = var.capacity.cpu_scale_out_pct > var.capacity.cpu_scale_in_pct && var.capacity.cpu_scale_in_pct >= 5 && var.capacity.cpu_scale_out_pct <= 95
    error_message = "capacity.cpu_scale_out_pct must be greater than cpu_scale_in_pct, with values between 5 and 95."
  }

  validation {
    condition     = var.capacity.mem_scale_out_pct > var.capacity.mem_scale_in_pct && var.capacity.mem_scale_in_pct >= 5 && var.capacity.mem_scale_out_pct <= 95
    error_message = "capacity.mem_scale_out_pct must be greater than mem_scale_in_pct, with values between 5 and 95."
  }

  validation {
    condition     = var.capacity.http_queue_scale_out == null || var.capacity.http_queue_scale_out > 0
    error_message = "capacity.http_queue_scale_out must be positive when set."
  }
}

# ------------------------------------------------------------------------------
# Availability & Resilience
# ------------------------------------------------------------------------------

variable "availability" {
  description = "High availability and load-balancing configuration."
  type = object({
    zone_redundant          = optional(bool, false)
    always_on               = optional(bool, true)
    client_affinity_enabled = optional(bool, false)
    load_balancing_mode     = optional(string, "LeastRequests")
  })
  default = {}

  validation {
    condition = contains([
      "WeightedRoundRobin",
      "LeastRequests",
      "LeastResponseTime",
      "WeightedTotalTraffic",
      "RequestHash",
      "PerSiteRoundRobin"
    ], var.availability.load_balancing_mode)
    error_message = "availability.load_balancing_mode must be a valid Azure App Service load balancing mode."
  }
}

# ------------------------------------------------------------------------------
# Health & Self-Healing
# ------------------------------------------------------------------------------

variable "health" {
  description = "Health probe, unhealthy-worker eviction, and container startup controls."
  type = object({
    path                         = optional(string, "/healthz")
    eviction_time_in_min         = optional(number, 5)
    max_ping_failures            = optional(number, 3)
    max_unhealthy_worker_percent = optional(number, 50)
    startup_timeout_seconds      = optional(number, 230)
    expected_status_code         = optional(number, 200)
  })
  default = {}

  validation {
    condition     = var.health.path == null || startswith(var.health.path, "/")
    error_message = "health.path must start with '/' (e.g. '/healthz')."
  }

  validation {
    condition     = var.health.eviction_time_in_min >= 2 && var.health.eviction_time_in_min <= 10
    error_message = "health.eviction_time_in_min must be between 2 and 10 minutes (Azure App Service constraint)."
  }

  validation {
    condition     = var.health.max_ping_failures >= 2 && var.health.max_ping_failures <= 10
    error_message = "health.max_ping_failures must be between 2 and 10."
  }

  validation {
    condition     = var.health.max_unhealthy_worker_percent >= 10 && var.health.max_unhealthy_worker_percent <= 100
    error_message = "health.max_unhealthy_worker_percent must be between 10 and 100."
  }

  validation {
    condition     = var.health.startup_timeout_seconds >= 30 && var.health.startup_timeout_seconds <= 1800
    error_message = "health.startup_timeout_seconds must be between 30 and 1800 seconds."
  }
}

# ------------------------------------------------------------------------------
# Rollouts (Blue/Green Deployment Slot & Swap Safety)
# ------------------------------------------------------------------------------

variable "rollout" {
  description = "Zero-downtime deployment slot and swap warm-up settings."
  type = object({
    staging_slot_enabled    = optional(bool, true)
    staging_slot_name       = optional(string, "staging")
    staging_container_image = optional(string)
    staging_app_settings    = optional(map(string), {})
    auto_swap_enabled       = optional(bool, false)
    warmup_ping_path        = optional(string)
    warmup_ping_statuses    = optional(string, "200")
  })
  default = {}

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.rollout.staging_slot_name)) && var.rollout.staging_slot_name != "production"
    error_message = "rollout.staging_slot_name must be 2-21 lowercase alphanumeric/hyphen characters and cannot be 'production'."
  }

  validation {
    condition     = var.rollout.warmup_ping_path == null || startswith(var.rollout.warmup_ping_path, "/")
    error_message = "rollout.warmup_ping_path must start with '/'."
  }
}

# ------------------------------------------------------------------------------
# Observability (Logs, APM, Synthetic Probes & SRE Alerts)
# ------------------------------------------------------------------------------

variable "observability" {
  description = "Logging, Application Insights, synthetic availability monitoring, and SRE metric alerts."
  type = object({
    log_analytics_workspace_id = optional(string)
    log_retention_days         = optional(number, 30)
    app_insights_enabled       = optional(bool, true)
    app_insights_sampling_pct  = optional(number, 100)
    http_logs_retention_days   = optional(number, 7)
    application_log_level      = optional(string, "Information")
    detailed_error_messages    = optional(bool, true)
    failed_request_tracing     = optional(bool, false)

    availability_test_enabled       = optional(bool, true)
    availability_test_frequency_sec = optional(number, 300)
    availability_test_timeout_sec   = optional(number, 30)
    availability_test_locations = optional(list(string), [
      "us-va-ash-azr",
      "us-tx-sn1-azr",
      "us-il-ch1-azr",
      "emea-nl-ams-azr",
      "emea-gb-db3-azr"
    ])
    ssl_cert_warning_days = optional(number, 14)

    alerts_enabled         = optional(bool, true)
    alert_action_group_ids = optional(list(string), [])
    alert_emails           = optional(list(string), [])
    alert_webhook_url      = optional(string)
    alert_thresholds = optional(object({
      http_5xx_count        = optional(number, 5)
      response_time_seconds = optional(number, 2.0)
      health_check_pct      = optional(number, 80)
      cpu_pct               = optional(number, 85)
      memory_pct            = optional(number, 85)
      availability_pct      = optional(number, 80)
    }), {})
  })
  default = {}

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.observability.log_retention_days)
    error_message = "observability.log_retention_days must be one of the Azure Application Insights supported values: 30, 60, 90, 120, 180, 270, 365, 550, or 730."
  }

  validation {
    condition     = contains(["Off", "Error", "Warning", "Information", "Verbose"], var.observability.application_log_level)
    error_message = "observability.application_log_level must be one of: Off, Error, Warning, Information, Verbose."
  }

  validation {
    condition     = contains([300, 600, 900], var.observability.availability_test_frequency_sec)
    error_message = "observability.availability_test_frequency_sec must be 300, 600, or 900 seconds."
  }

  validation {
    condition     = var.observability.availability_test_timeout_sec >= 30 && var.observability.availability_test_timeout_sec <= 120
    error_message = "observability.availability_test_timeout_sec must be between 30 and 120 seconds."
  }

  validation {
    condition     = var.observability.app_insights_sampling_pct >= 0 && var.observability.app_insights_sampling_pct <= 100
    error_message = "observability.app_insights_sampling_pct must be between 0 and 100."
  }
}

# ------------------------------------------------------------------------------
# Networking & Security Controls
# ------------------------------------------------------------------------------

variable "networking" {
  description = "Network exposure, VNet integration, Private Endpoint, IP access restrictions, and CORS."
  type = object({
    public_network_access_enabled     = optional(bool, true)
    minimum_tls_version               = optional(string, "1.2")
    http2_enabled                     = optional(bool, true)
    websockets_enabled                = optional(bool, false)
    vnet_subnet_id                    = optional(string)
    vnet_route_all_enabled            = optional(bool, true)
    private_endpoint_subnet_id        = optional(string)
    private_dns_zone_id               = optional(string)
    ip_restriction_default_action     = optional(string, "Allow")
    scm_use_main_ip_restriction       = optional(bool, false)
    scm_ip_restriction_default_action = optional(string, "Allow")
    ip_restrictions = optional(list(object({
      name                      = string
      priority                  = number
      action                    = optional(string, "Allow")
      ip_address                = optional(string)
      service_tag               = optional(string)
      virtual_network_subnet_id = optional(string)
    })), [])
    scm_ip_restrictions = optional(list(object({
      name                      = string
      priority                  = number
      action                    = optional(string, "Allow")
      ip_address                = optional(string)
      service_tag               = optional(string)
      virtual_network_subnet_id = optional(string)
    })), [])
    cors = optional(object({
      allowed_origins     = list(string)
      support_credentials = optional(bool, false)
    }))
  })
  default = {}

  validation {
    condition     = contains(["1.2", "1.3"], var.networking.minimum_tls_version)
    error_message = "networking.minimum_tls_version must be '1.2' or '1.3'."
  }

  validation {
    condition     = contains(["Allow", "Deny"], var.networking.ip_restriction_default_action) && contains(["Allow", "Deny"], var.networking.scm_ip_restriction_default_action)
    error_message = "IP restriction default actions must be 'Allow' or 'Deny'."
  }
}
