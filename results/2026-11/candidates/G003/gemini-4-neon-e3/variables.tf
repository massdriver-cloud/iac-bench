# ------------------------------------------------------------------------------
# Required Inputs
# ------------------------------------------------------------------------------

variable "service_name" {
  description = "Logical name of the HTTP API service (lowercase alphanumeric and hyphens, 3-22 characters)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-22 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,8}[a-z0-9]$", var.environment))
    error_message = "environment must be 2-10 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed (e.g. eastus2, westeurope)."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must be a non-empty Azure region name."
  }
}

variable "container" {
  description = "Container image and runtime configuration for the HTTP API."
  type = object({
    image                      = string
    registry_url               = optional(string, "https://mcr.microsoft.com")
    port                       = optional(number, 8080)
    startup_command            = optional(string, null)
    startup_timeout_seconds    = optional(number, 230)
    enable_persistent_storage  = optional(bool, false)
    acr_id                     = optional(string, null)
    use_managed_identity       = optional(bool, null)
    managed_identity_client_id = optional(string, null)
    registry_username          = optional(string, null)
  })

  validation {
    condition     = length(trimspace(var.container.image)) > 0 && !startswith(var.container.image, "http")
    error_message = "container.image must be a non-empty image reference (e.g. 'org/service:1.2.3') without a URL scheme."
  }

  validation {
    condition     = can(regex("^https://", var.container.registry_url))
    error_message = "container.registry_url must start with 'https://'."
  }

  validation {
    condition     = var.container.port >= 1 && var.container.port <= 65535
    error_message = "container.port must be between 1 and 65535."
  }

  validation {
    condition     = var.container.startup_timeout_seconds >= 30 && var.container.startup_timeout_seconds <= 1800
    error_message = "container.startup_timeout_seconds must be between 30 and 1800 seconds."
  }
}

# ------------------------------------------------------------------------------
# Naming, Resource Group & Tagging
# ------------------------------------------------------------------------------

variable "name_suffix" {
  description = "Optional fixed suffix for globally unique Azure resource names. If null, a 4-character lowercase alphanumeric suffix is generated."
  type        = string
  default     = null

  validation {
    condition     = var.name_suffix == null || can(regex("^[a-z0-9]{0,6}$", var.name_suffix))
    error_message = "name_suffix must be null or 0-6 lowercase alphanumeric characters."
  }
}

variable "create_resource_group" {
  description = "Whether to create a new Resource Group. Set to false and provide resource_group_name to deploy into an existing Resource Group."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Resource Group name. Optional when create_resource_group is true (defaults to rg-<service>-<env>); required when create_resource_group is false."
  type        = string
  default     = null

  validation {
    condition     = var.create_resource_group || (var.resource_group_name != null && length(trimspace(var.resource_group_name)) > 0)
    error_message = "resource_group_name must be provided when create_resource_group is false."
  }
}

variable "tags" {
  description = "Additional Azure resource tags merged with standard module tags."
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Capacity, Availability & Autoscaling
# ------------------------------------------------------------------------------

variable "capacity" {
  description = "Compute sizing, high availability, and autoscaling configuration."
  type = object({
    existing_service_plan_id = optional(string, null)
    sku_name                 = optional(string, "P1v3")
    zone_redundant           = optional(bool, false)
    min_instances            = optional(number, 2)
    max_instances            = optional(number, 10)
    autoscale = optional(object({
      enabled                  = optional(bool, true)
      cpu_scale_out_percent    = optional(number, 70)
      cpu_scale_in_percent     = optional(number, 30)
      memory_scale_out_percent = optional(number, 80)
      memory_scale_in_percent  = optional(number, 50)
      http_queue_scale_out     = optional(number, 100)
      cooldown_minutes         = optional(number, 5)
    }), {})
  })
  default = {}

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "P1v2", "P2v2", "P3v2",
      "P0v3", "P1v3", "P2v3", "P3v3",
      "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
      "I1v2", "I2v2", "I3v2"
    ], var.capacity.sku_name)
    error_message = "capacity.sku_name must be a supported Linux App Service Plan SKU (B1-B3, S1-S3, P1v2-P3v2, P0v3-P3v3, P1mv3-P5mv3, I1v2-I3v2)."
  }

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances && var.capacity.max_instances <= 30
    error_message = "capacity.min_instances must be >= 1, and capacity.max_instances must be between min_instances and 30."
  }

  validation {
    condition = !var.capacity.zone_redundant || contains([
      "P1v2", "P2v2", "P3v2",
      "P1v3", "P2v3", "P3v3",
      "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
      "I1v2", "I2v2", "I3v2"
    ], var.capacity.sku_name)
    error_message = "capacity.zone_redundant requires a Premium v2/v3 (excluding P0v3) or Isolated v2 SKU."
  }

  validation {
    condition     = !var.capacity.zone_redundant || (var.capacity.min_instances >= 3 && var.capacity.min_instances % 3 == 0 && var.capacity.max_instances % 3 == 0)
    error_message = "When capacity.zone_redundant is true, min_instances must be >= 3 and both min_instances and max_instances must be multiples of 3."
  }

  validation {
    condition     = var.capacity.existing_service_plan_id != null || !var.capacity.autoscale.enabled || !startswith(var.capacity.sku_name, "B")
    error_message = "Autoscaling requires a Standard, Premium, or Isolated SKU (Basic SKUs B1-B3 do not support Azure Monitor Autoscale)."
  }

  validation {
    condition     = var.capacity.autoscale.cpu_scale_in_percent < var.capacity.autoscale.cpu_scale_out_percent && var.capacity.autoscale.memory_scale_in_percent < var.capacity.autoscale.memory_scale_out_percent
    error_message = "Autoscale scale-in thresholds must be strictly less than scale-out thresholds."
  }
}

# ------------------------------------------------------------------------------
# Health Probes, Auto-Heal & Synthetic Monitoring
# ------------------------------------------------------------------------------

variable "health" {
  description = "Health probe, instance eviction, auto-heal, and synthetic availability check configuration."
  type = object({
    path                   = optional(string, "/healthz")
    eviction_time_minutes  = optional(number, 2)
    max_ping_failures      = optional(number, 3)
    auto_heal_enabled      = optional(bool, false)
    auto_heal_5xx_count    = optional(number, 50)
    auto_heal_5xx_interval = optional(string, "00:05:00")
    synthetic_probe = optional(object({
      enabled                 = optional(bool, true)
      frequency_seconds       = optional(number, 300)
      timeout_seconds         = optional(number, 30)
      expected_status_code    = optional(number, 200)
      ssl_cert_remaining_days = optional(number, 14)
      geo_locations           = optional(list(string), ["us-va-ash-azr", "us-ca-sjc-azr", "emea-nl-ams-azr"])
    }), {})
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

  validation {
    condition     = var.health.max_ping_failures >= 2 && var.health.max_ping_failures <= 10
    error_message = "health.max_ping_failures must be between 2 and 10."
  }

  validation {
    condition     = contains([300, 600, 900], var.health.synthetic_probe.frequency_seconds)
    error_message = "health.synthetic_probe.frequency_seconds must be 300, 600, or 900."
  }

  validation {
    condition     = var.health.synthetic_probe.timeout_seconds >= 30 && var.health.synthetic_probe.timeout_seconds <= 120
    error_message = "health.synthetic_probe.timeout_seconds must be between 30 and 120."
  }
}

# ------------------------------------------------------------------------------
# Rollouts & Deployment Slots
# ------------------------------------------------------------------------------

variable "rollout" {
  description = "Deployment slot, swap warmup, and sticky setting configuration for zero-downtime rollouts."
  type = object({
    staging_slot_enabled     = optional(bool, true)
    staging_slot_name        = optional(string, "staging")
    staging_image            = optional(string, null)
    warmup_path              = optional(string, null)
    warmup_statuses          = optional(string, "200")
    sticky_app_setting_names = optional(list(string), [])
    staging_app_settings     = optional(map(string), {})
  })
  default = {}

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,8}[a-z0-9]$", var.rollout.staging_slot_name))
    error_message = "rollout.staging_slot_name must be 3-10 lowercase alphanumeric characters or hyphens."
  }

  validation {
    condition     = var.rollout.warmup_path == null || startswith(var.rollout.warmup_path, "/")
    error_message = "rollout.warmup_path must be null or start with '/'."
  }

  validation {
    condition     = !var.rollout.staging_slot_enabled || var.capacity.existing_service_plan_id != null || !startswith(var.capacity.sku_name, "B")
    error_message = "Deployment slots require a Standard, Premium, or Isolated SKU (Basic SKUs B1-B3 do not support deployment slots)."
  }
}

# ------------------------------------------------------------------------------
# Observability, Diagnostics & SRE Alerting
# ------------------------------------------------------------------------------

variable "observability" {
  description = "Log Analytics, Application Insights, diagnostic settings, and SRE metric alerting configuration."
  type = object({
    enabled                             = optional(bool, true)
    existing_log_analytics_workspace_id = optional(string, null)
    log_retention_days                  = optional(number, 30)
    sampling_percentage                 = optional(number, 100)
    app_log_level                       = optional(string, "Information")
    alerts = optional(object({
      enabled                        = optional(bool, true)
      existing_action_group_ids      = optional(list(string), [])
      email_receivers                = optional(list(object({ name = string, email_address = string })), [])
      webhook_receivers              = optional(list(object({ name = string, service_uri = string })), [])
      http_5xx_threshold             = optional(number, 10)
      latency_threshold_seconds      = optional(number, 2)
      cpu_threshold_percent          = optional(number, 85)
      memory_threshold_percent       = optional(number, 85)
      availability_threshold_percent = optional(number, 90)
    }), {})
  })
  default = {}

  validation {
    condition     = var.observability.log_retention_days >= 30 && var.observability.log_retention_days <= 730
    error_message = "observability.log_retention_days must be between 30 and 730."
  }

  validation {
    condition     = var.observability.sampling_percentage >= 0 && var.observability.sampling_percentage <= 100
    error_message = "observability.sampling_percentage must be between 0 and 100."
  }

  validation {
    condition     = contains(["Off", "Error", "Warning", "Information", "Verbose"], var.observability.app_log_level)
    error_message = "observability.app_log_level must be one of Off, Error, Warning, Information, Verbose."
  }
}

# ------------------------------------------------------------------------------
# Networking, Access Control & Custom Domains
# ------------------------------------------------------------------------------

variable "networking" {
  description = "Ingress, outbound VNet integration, IP access restrictions, CORS, and custom domains."
  type = object({
    public_network_access_enabled = optional(bool, true)
    vnet_integration_subnet_id    = optional(string, null)
    vnet_image_pull_enabled       = optional(bool, false)
    websockets_enabled            = optional(bool, false)
    ip_restriction_default_action = optional(string, "Allow")
    ip_restrictions = optional(list(object({
      name                      = string
      priority                  = number
      action                    = optional(string, "Allow")
      ip_address                = optional(string, null)
      service_tag               = optional(string, null)
      virtual_network_subnet_id = optional(string, null)
    })), [])
    cors = optional(object({
      allowed_origins     = list(string)
      support_credentials = optional(bool, false)
    }), null)
    custom_domains = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = contains(["Allow", "Deny"], var.networking.ip_restriction_default_action)
    error_message = "networking.ip_restriction_default_action must be 'Allow' or 'Deny'."
  }
}

# ------------------------------------------------------------------------------
# Security, Identity & Application Configuration
# ------------------------------------------------------------------------------

variable "security" {
  description = "TLS policy, Managed Identities, and Key Vault secret references."
  type = object({
    minimum_tls_version             = optional(string, "1.2")
    user_assigned_identity_ids      = optional(list(string), [])
    key_vault_id                    = optional(string, null)
    key_vault_reference_identity_id = optional(string, null)
    key_vault_secrets               = optional(map(string), {})
  })
  default = {}

  validation {
    condition     = contains(["1.2", "1.3"], var.security.minimum_tls_version)
    error_message = "security.minimum_tls_version must be '1.2' or '1.3'."
  }
}

variable "app_settings" {
  description = "Non-sensitive environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "sensitive_app_settings" {
  description = "Sensitive environment variables injected into the container. Prefer security.key_vault_secrets when storing secrets in Azure Key Vault."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "container_registry_password" {
  description = "Optional password for private non-ACR container registries. Ignored when pulling via Managed Identity."
  type        = string
  default     = null
  sensitive   = true
}
