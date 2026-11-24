# =============================================================================
# Core Service Identity
# =============================================================================

variable "service_name" {
  description = "Short logical name of the HTTP service (lowercase letters, numbers, and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-30 characters, start with a letter, end with a letter or digit, and contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.environment))
    error_message = "environment must be 2-15 lowercase alphanumeric characters or hyphens, starting with a letter."
  }
}

variable "location" {
  description = "Azure region where the service is deployed (e.g. eastus2, westeurope)."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must be a non-empty Azure region name."
  }
}

variable "name_suffix" {
  description = "Optional custom suffix appended to globally unique resource names. If null, a random 4-character suffix is generated."
  type        = string
  default     = null

  validation {
    condition     = var.name_suffix == null || can(regex("^[a-z0-9]{2,8}$", var.name_suffix))
    error_message = "name_suffix must be 2-8 lowercase alphanumeric characters."
  }
}

variable "resource_group" {
  description = "Resource group placement. By default, creates a dedicated resource group for the service."
  type = object({
    create = optional(bool, true)
    name   = optional(string)
  })
  default = {}

  validation {
    condition     = var.resource_group.create || (var.resource_group.name != null && length(trimspace(var.resource_group.name)) > 0)
    error_message = "resource_group.name must be provided when resource_group.create is false."
  }
}

variable "tags" {
  description = "Additional tags applied to all created resources. Merged with standard SRE service tags."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Container Image & Runtime Configuration
# =============================================================================

variable "container" {
  description = "Container image and runtime configuration for the HTTP API."
  type = object({
    image                        = string
    registry_url                 = optional(string, "https://index.docker.io")
    port                         = optional(number, 8080)
    startup_command              = optional(string)
    use_managed_identity_for_acr = optional(bool)
    registry_username            = optional(string)
  })

  validation {
    condition     = length(trimspace(var.container.image)) > 0
    error_message = "container.image must be a non-empty image reference (e.g. 'org/service:1.2.3')."
  }

  validation {
    condition     = can(regex("^https://", var.container.registry_url))
    error_message = "container.registry_url must start with 'https://'."
  }

  validation {
    condition     = var.container.port >= 1 && var.container.port <= 65535
    error_message = "container.port must be a valid TCP port between 1 and 65535."
  }
}

variable "container_registry_password" {
  description = "Password or token for private non-ACR container registries. Leave null when pulling from public registries or ACR via Managed Identity."
  type        = string
  default     = null
  sensitive   = true
}

variable "app_settings" {
  description = "Non-sensitive environment variables injected into the container. Use key_vault_secrets for sensitive values."
  type        = map(string)
  default     = {}
}

variable "key_vault_secrets" {
  description = "Map of environment variable names to Azure Key Vault secret URIs (e.g. 'https://myvault.vault.azure.net/secrets/db-password'). Automatically formatted as Key Vault references."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for _, uri in var.key_vault_secrets : can(regex("^https://[a-zA-Z0-9-]+\\.vault\\.azure\\.net/secrets/", uri))
    ])
    error_message = "Each key_vault_secrets value must be a valid Azure Key Vault secret URI (https://<vault>.vault.azure.net/secrets/<name>[/<version>])."
  }
}

# =============================================================================
# Capacity & Availability
# =============================================================================

variable "availability" {
  description = "Availability posture controlling zone redundancy and minimum instance distribution. Valid tiers: 'zone_redundant' (3+ instances across AZs), 'multi_instance' (2+ instances), 'single_instance' (1 instance, non-prod)."
  type = object({
    tier = optional(string, "zone_redundant")
  })
  default = {}

  validation {
    condition     = contains(["zone_redundant", "multi_instance", "single_instance"], var.availability.tier)
    error_message = "availability.tier must be one of: zone_redundant, multi_instance, single_instance."
  }
}

variable "capacity" {
  description = "Compute sizing and autoscaling policy. Sizes map to Premium v3 compute profiles: micro (1 vCPU/4 GB), small (2 vCPU/8 GB), medium (4 vCPU/16 GB), large (8 vCPU/32 GB)."
  type = object({
    size                       = optional(string, "small")
    min_instances              = optional(number)
    max_instances              = optional(number)
    autoscale_enabled          = optional(bool, true)
    cpu_scale_out_percent      = optional(number, 70)
    cpu_scale_in_percent       = optional(number, 30)
    memory_scale_out_percent   = optional(number, 80)
    scale_out_cooldown_minutes = optional(number, 5)
    scale_in_cooldown_minutes  = optional(number, 10)
    existing_service_plan_id   = optional(string)
  })
  default = {}

  validation {
    condition     = contains(["micro", "small", "medium", "large"], var.capacity.size)
    error_message = "capacity.size must be one of: micro, small, medium, large."
  }

  validation {
    condition     = var.capacity.min_instances == null || (var.capacity.min_instances >= 1 && var.capacity.min_instances <= 30)
    error_message = "capacity.min_instances must be between 1 and 30."
  }

  validation {
    condition     = var.capacity.max_instances == null || (var.capacity.max_instances >= 1 && var.capacity.max_instances <= 30)
    error_message = "capacity.max_instances must be between 1 and 30."
  }

  validation {
    condition = (
      var.capacity.min_instances == null ||
      var.capacity.max_instances == null ||
      var.capacity.max_instances >= var.capacity.min_instances
    )
    error_message = "capacity.max_instances must be greater than or equal to capacity.min_instances."
  }

  validation {
    condition     = var.capacity.cpu_scale_in_percent < var.capacity.cpu_scale_out_percent
    error_message = "capacity.cpu_scale_in_percent must be strictly less than capacity.cpu_scale_out_percent to prevent thrashing."
  }

  validation {
    condition     = var.capacity.cpu_scale_out_percent >= 20 && var.capacity.cpu_scale_out_percent <= 95 && var.capacity.memory_scale_out_percent >= 20 && var.capacity.memory_scale_out_percent <= 95
    error_message = "Scale-out thresholds must be between 20 and 95 percent."
  }
}

# =============================================================================
# Health Probes & Startup Behavior
# =============================================================================

variable "health" {
  description = "HTTP health check probe, instance eviction, load balancing, and container startup warmup behavior."
  type = object({
    path                    = optional(string, "/healthz")
    eviction_time_in_min    = optional(number, 2)
    startup_timeout_seconds = optional(number, 230)
    warmup_statuses         = optional(string, "200")
    warmup_max_retries      = optional(number, 3)
    load_balancing_mode     = optional(string, "LeastRequests")
  })
  default = {}

  validation {
    condition     = startswith(var.health.path, "/")
    error_message = "health.path must start with '/'."
  }

  validation {
    condition     = var.health.eviction_time_in_min >= 2 && var.health.eviction_time_in_min <= 10
    error_message = "health.eviction_time_in_min must be between 2 and 10 minutes (Azure App Service constraint)."
  }

  validation {
    condition     = var.health.startup_timeout_seconds >= 30 && var.health.startup_timeout_seconds <= 1800
    error_message = "health.startup_timeout_seconds must be between 30 and 1800 seconds."
  }

  validation {
    condition     = contains(["LeastRequests", "WeightedRoundRobin", "WeightedTotalTraffic", "RequestHash", "PerSiteRoundRobin"], var.health.load_balancing_mode)
    error_message = "health.load_balancing_mode must be a valid Azure App Service load balancing mode."
  }
}

# =============================================================================
# Rollouts (Zero-Downtime Staging Slot)
# =============================================================================

variable "rollouts" {
  description = "Zero-downtime rollout configuration using a dedicated deployment slot with warm-up checks and sticky slot settings."
  type = object({
    enable_staging_slot           = optional(bool, true)
    staging_slot_name             = optional(string, "staging")
    staging_image                 = optional(string)
    auto_swap_enabled             = optional(bool, false)
    sticky_app_setting_names      = optional(list(string), [])
    staging_app_settings          = optional(map(string), {})
    staging_public_access_enabled = optional(bool)
    staging_ip_restrictions = optional(list(object({
      name        = string
      ip_address  = optional(string)
      subnet_id   = optional(string)
      service_tag = optional(string)
      priority    = number
      action      = optional(string, "Allow")
    })), [])
  })
  default = {}

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.rollouts.staging_slot_name))
    error_message = "rollouts.staging_slot_name must be 2-21 lowercase alphanumeric characters or hyphens, starting with a letter."
  }

  validation {
    condition = alltrue([
      for r in var.rollouts.staging_ip_restrictions :
      length(compact([r.ip_address, r.subnet_id, r.service_tag])) == 1
    ])
    error_message = "Each rollouts.staging_ip_restrictions rule must specify exactly one of ip_address, subnet_id, or service_tag."
  }
}

# =============================================================================
# Observability (Logs, Telemetry, Diagnostics & Golden-Signal Alerts)
# =============================================================================

variable "observability" {
  description = "Logging, Application Insights telemetry, platform diagnostic settings, SRE golden-signal metric alerts, and optional synthetic availability probes."
  type = object({
    existing_log_analytics_workspace_id = optional(string)
    log_retention_days                  = optional(number, 30)
    enable_application_insights         = optional(bool, true)
    app_insights_sampling_percentage    = optional(number, 100)
    enable_alerts                       = optional(bool, true)
    action_group_ids                    = optional(list(string), [])
    alert_email_receivers = optional(list(object({
      name          = string
      email_address = string
    })), [])
    alert_webhook_receivers = optional(list(object({
      name        = string
      service_uri = string
    })), [])
    alert_thresholds = optional(object({
      http_5xx_count        = optional(number, 10)
      avg_response_time_sec = optional(number, 2.0)
      health_check_min_pct  = optional(number, 99)
      plan_cpu_percent      = optional(number, 85)
      plan_memory_percent   = optional(number, 85)
    }), {})
    synthetic_check = optional(object({
      enabled           = optional(bool, false)
      frequency_seconds = optional(number, 300)
      timeout_seconds   = optional(number, 30)
      expected_status   = optional(number, 200)
      geo_locations     = optional(list(string), ["us-va-ash-azr", "us-tx-sn1-azr", "emea-nl-ams-azr"])
    }), {})
  })
  default = {}

  validation {
    condition     = var.observability.log_retention_days >= 30 && var.observability.log_retention_days <= 730
    error_message = "observability.log_retention_days must be between 30 and 730 days."
  }

  validation {
    condition     = var.observability.app_insights_sampling_percentage > 0 && var.observability.app_insights_sampling_percentage <= 100
    error_message = "observability.app_insights_sampling_percentage must be between 1 and 100."
  }

  validation {
    condition     = contains([300, 600, 900], var.observability.synthetic_check.frequency_seconds)
    error_message = "observability.synthetic_check.frequency_seconds must be 300, 600, or 900."
  }

  validation {
    condition     = var.observability.synthetic_check.timeout_seconds >= 5 && var.observability.synthetic_check.timeout_seconds <= 120
    error_message = "observability.synthetic_check.timeout_seconds must be between 5 and 120 seconds."
  }

  validation {
    condition     = length(var.observability.synthetic_check.geo_locations) >= 1
    error_message = "observability.synthetic_check.geo_locations must contain at least one Azure probe location."
  }
}

# =============================================================================
# Networking & Identity
# =============================================================================

variable "network" {
  description = "Ingress access controls, regional VNet integration, private ACR image pulls, and CORS settings."
  type = object({
    public_access_enabled      = optional(bool, true)
    vnet_integration_subnet_id = optional(string)
    vnet_image_pull_enabled    = optional(bool, false)
    ip_restrictions = optional(list(object({
      name        = string
      ip_address  = optional(string)
      subnet_id   = optional(string)
      service_tag = optional(string)
      priority    = number
      action      = optional(string, "Allow")
    })), [])
    cors_allowed_origins     = optional(list(string), [])
    cors_support_credentials = optional(bool, false)
  })
  default = {}

  validation {
    condition     = !var.network.vnet_image_pull_enabled || var.network.vnet_integration_subnet_id != null
    error_message = "network.vnet_image_pull_enabled requires network.vnet_integration_subnet_id to be set."
  }

  validation {
    condition = alltrue([
      for r in var.network.ip_restrictions :
      length(compact([r.ip_address, r.subnet_id, r.service_tag])) == 1
    ])
    error_message = "Each network.ip_restrictions rule must specify exactly one of ip_address, subnet_id, or service_tag."
  }
}

variable "identity" {
  description = "Managed identity configuration. System-assigned managed identity is always enabled; attach optional user-assigned identities for shared RBAC (e.g. ACR pull or Key Vault access across slots)."
  type = object({
    user_assigned_identity_ids      = optional(list(string), [])
    key_vault_reference_identity_id = optional(string)
    acr_pull_identity_client_id     = optional(string)
  })
  default = {}
}
