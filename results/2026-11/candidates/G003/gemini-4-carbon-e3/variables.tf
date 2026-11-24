# -----------------------------------------------------------------------------
# Core Service Identity & Placement
# -----------------------------------------------------------------------------

variable "service_name" {
  description = "Short canonical name of the web service (e.g. 'orders-api'). Used in Azure resource naming, tags, and OpenTelemetry service metadata."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,36}[a-z0-9])?$", var.service_name))
    error_message = "service_name must be 1-38 lowercase alphanumeric characters or hyphens, starting and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment identifier (e.g. 'dev', 'staging', 'prod')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", var.environment))
    error_message = "environment must be 1-16 lowercase alphanumeric characters or hyphens, starting and ending with an alphanumeric character."
  }
}

variable "location" {
  description = "Azure region in which the App Service and supporting resources are deployed (e.g. 'eastus2', 'westeurope')."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must be a non-empty Azure region name."
  }
}

variable "create_resource_group" {
  description = "Whether to create a dedicated Resource Group for this service. Set to false to deploy into an existing Resource Group specified by resource_group_name."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Custom name for the created Resource Group, or the name of an existing Resource Group when create_resource_group is false. Defaults to 'rg-<service_name>-<environment>'."
  type        = string
  default     = null
}

variable "custom_app_name" {
  description = "Optional explicit globally unique App Service name (<name>.azurewebsites.net). When omitted, a collision-safe name 'app-<service_name>-<environment>-<suffix>' is generated."
  type        = string
  default     = null

  validation {
    condition     = var.custom_app_name == null || can(regex("^[a-z0-9]([a-z0-9-]{0,58}[a-z0-9])?$", var.custom_app_name))
    error_message = "custom_app_name must be 2-60 lowercase alphanumeric characters or hyphens."
  }
}

variable "tags" {
  description = "Additional Azure resource tags merged with standard service, environment, and managed_by tags."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Container Runtime & Application Configuration
# -----------------------------------------------------------------------------

variable "container" {
  description = "Container image, registry settings, and runtime behavior for the HTTP API."
  type = object({
    image                          = string
    registry_url                   = optional(string, "https://mcr.microsoft.com")
    port                           = optional(number, 8080)
    startup_command                = optional(string)
    startup_time_limit_seconds     = optional(number, 230)
    enable_storage_mount           = optional(bool, false)
    websockets_enabled             = optional(bool, false)
    acr_use_managed_identity       = optional(bool, false)
    acr_managed_identity_client_id = optional(string)
    acr_id                         = optional(string)
    registry_username              = optional(string)
  })

  validation {
    condition     = length(trimspace(var.container.image)) > 0 && !startswith(var.container.image, "http://") && !startswith(var.container.image, "https://")
    error_message = "container.image must be a repository[:tag|@digest] reference without registry scheme (configure registry_url separately)."
  }

  validation {
    condition     = startswith(var.container.registry_url, "https://")
    error_message = "container.registry_url must use HTTPS (e.g. 'https://mcr.microsoft.com' or 'https://myregistry.azurecr.io')."
  }

  validation {
    condition     = var.container.port >= 1 && var.container.port <= 65535 && floor(var.container.port) == var.container.port
    error_message = "container.port must be an integer TCP port between 1 and 65535."
  }

  validation {
    condition     = var.container.startup_time_limit_seconds >= 30 && var.container.startup_time_limit_seconds <= 1800
    error_message = "container.startup_time_limit_seconds must be between 30 and 1800 seconds."
  }
}

variable "container_registry_password" {
  description = "Optional password or token for private container registries that do not support Azure Managed Identity."
  type        = string
  default     = null
  sensitive   = true
}

variable "app_settings" {
  description = "Non-sensitive environment variables injected into the container runtime."
  type        = map(string)
  default     = {}
}

variable "secret_app_settings" {
  description = "Sensitive environment variables injected into the container runtime. Prefer key_vault_secret_references in production."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "key_vault_secret_references" {
  description = "Map of environment variable names to Azure Key Vault Secret URIs, automatically formatted as @Microsoft.KeyVault(SecretUri=...)."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for uri in values(var.key_vault_secret_references) : startswith(uri, "https://")])
    error_message = "All values in key_vault_secret_references must be HTTPS Key Vault secret URIs."
  }
}

variable "key_vault_id" {
  description = "Optional Azure Key Vault resource ID. When set, grants 'Key Vault Secrets User' to the app and staging slot Managed Identities."
  type        = string
  default     = null
}

variable "key_vault_reference_identity_id" {
  description = "Optional User-Assigned Managed Identity resource ID used to resolve Key Vault secret references. Defaults to the System-Assigned identity."
  type        = string
  default     = null
}

variable "user_assigned_identity_ids" {
  description = "Optional list of User-Assigned Managed Identity resource IDs attached alongside the System-Assigned Managed Identity."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Capacity & Horizontal Scaling
# -----------------------------------------------------------------------------

variable "capacity" {
  description = "Compute tier, worker counts, and horizontal autoscale rules for the service."
  type = object({
    existing_service_plan_id       = optional(string)
    sku_name                       = optional(string, "P1v3")
    min_instances                  = optional(number, 3)
    max_instances                  = optional(number, 10)
    autoscale_enabled              = optional(bool, true)
    per_site_scaling_enabled       = optional(bool, false)
    cpu_scale_out_threshold        = optional(number, 70)
    cpu_scale_in_threshold         = optional(number, 30)
    memory_scale_out_threshold     = optional(number, 80)
    memory_scale_in_threshold      = optional(number, 40)
    http_queue_scale_out_threshold = optional(number, 100)
    scale_out_cooldown_minutes     = optional(number, 5)
    scale_in_cooldown_minutes      = optional(number, 10)
  })
  default = {}

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "P1v2", "P2v2", "P3v2",
      "P0v3", "P1v3", "P2v3", "P3v3",
      "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
      "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2"
    ], var.capacity.sku_name)
    error_message = "capacity.sku_name must be a valid Linux App Service SKU (B1-B3, S1-S3, P1v2-P3v2, P0v3-P3v3, P1mv3-P5mv3, or I1v2-I6v2)."
  }

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances && var.capacity.max_instances <= 100
    error_message = "capacity.min_instances must be >= 1 and capacity.max_instances must be between min_instances and 100."
  }

  validation {
    condition     = var.capacity.cpu_scale_in_threshold < var.capacity.cpu_scale_out_threshold && var.capacity.cpu_scale_out_threshold <= 95 && var.capacity.cpu_scale_in_threshold >= 5
    error_message = "CPU scale-in threshold (5-94) must be strictly lower than CPU scale-out threshold (<= 95)."
  }

  validation {
    condition     = var.capacity.memory_scale_in_threshold < var.capacity.memory_scale_out_threshold && var.capacity.memory_scale_out_threshold <= 95 && var.capacity.memory_scale_in_threshold >= 5
    error_message = "Memory scale-in threshold (5-94) must be strictly lower than memory scale-out threshold (<= 95)."
  }

  validation {
    condition     = var.capacity.scale_out_cooldown_minutes >= 1 && var.capacity.scale_out_cooldown_minutes <= 60 && var.capacity.scale_in_cooldown_minutes >= 1 && var.capacity.scale_in_cooldown_minutes <= 60
    error_message = "Autoscale cooldown periods must be between 1 and 60 minutes."
  }
}

# -----------------------------------------------------------------------------
# Availability, Resilience & Protocol Hardening
# -----------------------------------------------------------------------------

variable "availability" {
  description = "Availability zone redundancy, keep-alive, stateless load distribution, TLS/HTTP2 hardening, and automated self-healing."
  type = object({
    zone_redundant                  = optional(bool)
    always_on                       = optional(bool, true)
    client_affinity_enabled         = optional(bool, false)
    http2_enabled                   = optional(bool, true)
    minimum_tls_version             = optional(string, "1.2")
    auto_heal_enabled               = optional(bool, true)
    auto_heal_5xx_count             = optional(number, 50)
    auto_heal_5xx_interval          = optional(string, "00:02:00")
    auto_heal_slow_request_time     = optional(string, "00:00:30")
    auto_heal_slow_request_count    = optional(number, 25)
    auto_heal_slow_request_interval = optional(string, "00:02:00")
    auto_heal_startup_grace_period  = optional(string, "00:05:00")
  })
  default = {}

  validation {
    condition     = contains(["1.2", "1.3"], var.availability.minimum_tls_version)
    error_message = "availability.minimum_tls_version must be '1.2' or '1.3'."
  }
}

# -----------------------------------------------------------------------------
# Health Probing & Readiness
# -----------------------------------------------------------------------------

variable "health" {
  description = "Health check endpoint, unhealthy worker eviction window, container warmup path, and optional multi-region synthetic probing."
  type = object({
    path                          = optional(string, "/healthz")
    eviction_time_in_min          = optional(number, 5)
    warmup_path                   = optional(string)
    warmup_statuses               = optional(string, "200,204")
    synthetic_probe_enabled       = optional(bool, false)
    synthetic_probe_frequency_sec = optional(number, 300)
    synthetic_probe_locations = optional(list(string), [
      "us-tx-sn1-azr",
      "us-il-ch1-azr",
      "us-va-ash-azr"
    ])
  })
  default = {}

  validation {
    condition     = startswith(var.health.path, "/")
    error_message = "health.path must begin with '/' (e.g. '/healthz')."
  }

  validation {
    condition     = var.health.eviction_time_in_min >= 2 && var.health.eviction_time_in_min <= 10
    error_message = "health.eviction_time_in_min must be between 2 and 10 minutes (Azure App Service platform requirement)."
  }

  validation {
    condition     = contains([300, 600, 900], var.health.synthetic_probe_frequency_sec)
    error_message = "health.synthetic_probe_frequency_sec must be 300, 600, or 900 seconds."
  }
}

# -----------------------------------------------------------------------------
# Rollouts & Deployment Slots
# -----------------------------------------------------------------------------

variable "rollout" {
  description = "Blue/green deployment slot configuration, slot-specific settings, warmup-gated auto-swap, and CI/CD lifecycle controls."
  type = object({
    staging_slot_enabled           = optional(bool)
    staging_image                  = optional(string)
    staging_app_settings           = optional(map(string), {})
    auto_swap_enabled              = optional(bool, false)
    sticky_app_setting_names       = optional(list(string), [])
    sticky_connection_string_names = optional(list(string), [])
  })
  default = {}
}

# -----------------------------------------------------------------------------
# Networking, Access Control & Custom Domains
# -----------------------------------------------------------------------------

variable "network" {
  description = "Inbound network controls, VNet integration, Private Endpoint, CORS, and custom domain bindings."
  type = object({
    public_network_access_enabled     = optional(bool, true)
    vnet_integration_subnet_id        = optional(string)
    vnet_route_all_enabled            = optional(bool, true)
    vnet_image_pull_enabled           = optional(bool, false)
    private_endpoint_subnet_id        = optional(string)
    private_dns_zone_ids              = optional(list(string), [])
    ip_restriction_default_action     = optional(string, "Allow")
    scm_ip_restriction_default_action = optional(string, "Allow")
    scm_use_main_ip_restriction       = optional(bool, true)
    ip_restrictions = optional(list(object({
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
    custom_domains = optional(list(object({
      hostname                    = string
      managed_certificate_enabled = optional(bool, true)
    })), [])
  })
  default = {}

  validation {
    condition     = contains(["Allow", "Deny"], var.network.ip_restriction_default_action) && contains(["Allow", "Deny"], var.network.scm_ip_restriction_default_action)
    error_message = "IP restriction default actions must be either 'Allow' or 'Deny'."
  }
}

# -----------------------------------------------------------------------------
# Observability, Telemetry & Golden-Signal Alerting
# -----------------------------------------------------------------------------

variable "observability" {
  description = "Log Analytics workspace, Application Insights tracing, diagnostic log shipping, and golden-signal Azure Monitor alerts."
  type = object({
    existing_log_analytics_workspace_id = optional(string)
    log_retention_days                  = optional(number, 30)
    log_analytics_sku                   = optional(string, "PerGB2018")
    daily_log_quota_gb                  = optional(number, -1)
    application_insights_enabled        = optional(bool, true)
    sampling_percentage                 = optional(number, 100)
    http_logs_retention_days            = optional(number, 7)
    http_logs_max_size_mb               = optional(number, 100)
    alerts_enabled                      = optional(bool, true)
    action_group_ids                    = optional(list(string), [])
    alert_email_receivers               = optional(list(string), [])
    alert_webhook_uris                  = optional(list(string), [])
    http_5xx_threshold                  = optional(number, 10)
    response_time_threshold_seconds     = optional(number, 2.0)
    health_check_alert_threshold        = optional(number, 99)
    cpu_alert_threshold                 = optional(number, 85)
    memory_alert_threshold              = optional(number, 85)
  })
  default = {}

  validation {
    condition     = var.observability.log_retention_days >= 30 && var.observability.log_retention_days <= 730
    error_message = "observability.log_retention_days must be between 30 and 730 days."
  }

  validation {
    condition     = var.observability.sampling_percentage >= 0 && var.observability.sampling_percentage <= 100
    error_message = "observability.sampling_percentage must be between 0 and 100."
  }

  validation {
    condition     = var.observability.http_logs_max_size_mb >= 25 && var.observability.http_logs_max_size_mb <= 100
    error_message = "observability.http_logs_max_size_mb must be between 25 and 100 MB (Azure App Service limit)."
  }
}
