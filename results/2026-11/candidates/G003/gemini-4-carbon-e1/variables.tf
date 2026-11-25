# -----------------------------------------------------------------------------
# Core Service Identity (Required)
# -----------------------------------------------------------------------------

variable "service_name" {
  description = "Canonical short name of the service (for example, 'orders-api' or 'billing-gateway'). Used in resource naming, OpenTelemetry service attributes, and standard tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$", var.service_name))
    error_message = "service_name must be 1 to 40 characters, contain only lowercase letters, numbers, and hyphens, and start and end with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment identifier (for example, 'dev', 'staging', 'uat', or 'prod')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", var.environment))
    error_message = "environment must be 1 to 16 characters, contain only lowercase letters, numbers, and hyphens, and start and end with an alphanumeric character."
  }
}

variable "location" {
  description = "Azure region where the service and its supporting resources are deployed (for example, 'eastus2' or 'westeurope')."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must be a non-empty Azure region name."
  }
}

variable "application" {
  description = <<-EOT
    Workload specification for the web service.
    Configure `container` for containerized HTTP APIs (the standard SRE path, using Managed Identity ACR pull by default),
    or `runtime` for managed Linux language runtimes when a service is not yet containerized.
  EOT

  type = object({
    port            = optional(number, 8080)
    startup_command = optional(string)
    storage_mounted = optional(bool, false)

    container = optional(object({
      registry_url               = string
      image                      = string
      tag                        = string
      use_managed_identity       = optional(bool, true)
      managed_identity_client_id = optional(string)
      container_registry_id      = optional(string)
    }))

    runtime = optional(object({
      dotnet_version      = optional(string)
      node_version        = optional(string)
      python_version      = optional(string)
      go_version          = optional(string)
      java_version        = optional(string)
      java_server         = optional(string, "JAVA")
      java_server_version = optional(string)
    }))
  })

  validation {
    condition     = var.application.port >= 1 && var.application.port <= 65535 && floor(var.application.port) == var.application.port
    error_message = "application.port must be a valid TCP port integer between 1 and 65535."
  }

  validation {
    condition     = (var.application.container != null) != (var.application.runtime != null)
    error_message = "Exactly one of application.container or application.runtime must be configured."
  }

  validation {
    condition = var.application.container == null ? true : (
      startswith(var.application.container.registry_url, "https://") &&
      length(trimspace(var.application.container.image)) > 0 &&
      length(trimspace(var.application.container.tag)) > 0
    )
    error_message = "When application.container is set, registry_url must start with 'https://', and both image and tag must be non-empty."
  }

  validation {
    condition = var.application.runtime == null ? true : (
      length([
        for v in [
          var.application.runtime.dotnet_version,
          var.application.runtime.node_version,
          var.application.runtime.python_version,
          var.application.runtime.go_version,
          var.application.runtime.java_version,
        ] : v if v != null
      ]) == 1
    )
    error_message = "When application.runtime is set, exactly one language runtime version (dotnet_version, node_version, python_version, go_version, or java_version) must be specified."
  }
}

# -----------------------------------------------------------------------------
# Placement & Naming Overrides
# -----------------------------------------------------------------------------

variable "existing_resource_group_name" {
  description = "Optional name of an existing Azure Resource Group to deploy into. When null, a dedicated Resource Group is created for the service."
  type        = string
  default     = null

  validation {
    condition     = var.existing_resource_group_name == null || length(trimspace(coalesce(var.existing_resource_group_name, "x"))) > 0
    error_message = "existing_resource_group_name cannot be an empty string when provided."
  }
}

# -----------------------------------------------------------------------------
# Capacity & Horizontal Scaling
# -----------------------------------------------------------------------------

variable "capacity" {
  description = <<-EOT
    Compute sizing and horizontal autoscale behavior.
    Defaults to a dedicated Premium v3 plan (P1v3) running 3 baseline instances with automatic scale-out up to 10 instances
    driven by CPU, memory, and HTTP request queue pressure. Pass `existing_service_plan_id` to consolidate onto a shared plan.
  EOT

  type = object({
    existing_service_plan_id       = optional(string)
    sku_name                       = optional(string, "P1v3")
    min_instances                  = optional(number, 3)
    max_instances                  = optional(number, 10)
    per_site_scaling_enabled       = optional(bool, false)
    app_worker_count               = optional(number)
    autoscale_enabled              = optional(bool, true)
    cpu_scale_out_threshold        = optional(number, 70)
    cpu_scale_in_threshold         = optional(number, 30)
    memory_scale_out_threshold     = optional(number, 80)
    http_queue_scale_out_threshold = optional(number, 100)
    scale_out_cooldown             = optional(string, "PT5M")
    scale_in_cooldown              = optional(string, "PT10M")
  })
  default = {}

  validation {
    condition = contains([
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "P1v2", "P2v2", "P3v2",
      "P0v3", "P1v3", "P2v3", "P3v3",
      "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
      "P1v4", "P2v4", "P3v4",
      "P1mv4", "P2mv4", "P3mv4", "P4mv4", "P5mv4",
      "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2",
    ], var.capacity.sku_name)
    error_message = "capacity.sku_name must be a supported production-capable Linux App Service SKU (Basic B1-B3, Standard S1-S3, Premium v2/v3/v4, or Isolated v2)."
  }

  validation {
    condition = (
      var.capacity.min_instances >= 1 &&
      var.capacity.min_instances <= 30 &&
      var.capacity.max_instances >= var.capacity.min_instances &&
      var.capacity.max_instances <= 30
    )
    error_message = "capacity.min_instances must be between 1 and 30, and capacity.max_instances must be between min_instances and 30."
  }

  validation {
    condition = (
      var.capacity.cpu_scale_in_threshold >= 1 &&
      var.capacity.cpu_scale_out_threshold <= 99 &&
      var.capacity.cpu_scale_in_threshold < var.capacity.cpu_scale_out_threshold &&
      var.capacity.memory_scale_out_threshold >= 1 &&
      var.capacity.memory_scale_out_threshold <= 99 &&
      var.capacity.http_queue_scale_out_threshold >= 1
    )
    error_message = "Autoscale thresholds must be valid percentages (with cpu_scale_in_threshold < cpu_scale_out_threshold) and http_queue_scale_out_threshold >= 1."
  }
}

# -----------------------------------------------------------------------------
# Availability & Protocol Hardening
# -----------------------------------------------------------------------------

variable "availability" {
  description = <<-EOT
    Availability posture and HTTP transport defaults.
    Enables Availability Zone balancing across 3 AZs, Always On, HTTP/2, TLS 1.2+, 64-bit workers, and stateless load distribution (ARR client affinity disabled) by default.
  EOT

  type = object({
    zone_balancing_enabled  = optional(bool, true)
    always_on               = optional(bool, true)
    client_affinity_enabled = optional(bool, false)
    http2_enabled           = optional(bool, true)
    websockets_enabled      = optional(bool, false)
    minimum_tls_version     = optional(string, "1.2")
  })
  default = {}

  validation {
    condition     = contains(["1.2", "1.3"], var.availability.minimum_tls_version)
    error_message = "availability.minimum_tls_version must be '1.2' or '1.3'."
  }

  validation {
    condition = (
      !var.availability.zone_balancing_enabled ||
      var.capacity.existing_service_plan_id != null ||
      (
        contains([
          "P1v2", "P2v2", "P3v2",
          "P0v3", "P1v3", "P2v3", "P3v3",
          "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
          "P1v4", "P2v4", "P3v4",
          "P1mv4", "P2mv4", "P3mv4", "P4mv4", "P5mv4",
          "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2",
        ], var.capacity.sku_name) &&
        var.capacity.min_instances >= 3
      )
    )
    error_message = "When availability.zone_balancing_enabled is true on a module-managed Service Plan, capacity.sku_name must be a Premium v2/v3/v4 or Isolated v2 SKU and capacity.min_instances must be at least 3."
  }
}

# -----------------------------------------------------------------------------
# Health Probes & Automated Self-Healing
# -----------------------------------------------------------------------------

variable "health" {
  description = <<-EOT
    Load-balancer health probing, container startup grace window, and automated worker self-healing.
    Unhealthy instances failing probes on `path` are automatically evicted from rotation, and wedged workers exhibiting
    sustained 5xx bursts or hung requests are safely recycled after `minimum_process_execution_time`.
  EOT

  type = object({
    path                       = optional(string, "/healthz")
    eviction_time_in_min       = optional(number, 5)
    startup_time_limit_seconds = optional(number, 230)

    auto_heal = optional(object({
      enabled                        = optional(bool, true)
      minimum_process_execution_time = optional(string, "00:10:00")

      status_code_trigger = optional(object({
        status_code_range = optional(string, "500-599")
        count             = optional(number, 100)
        interval          = optional(string, "00:02:00")
      }), {})

      slow_request_trigger = optional(object({
        enabled    = optional(bool, true)
        time_taken = optional(string, "00:00:30")
        count      = optional(number, 50)
        interval   = optional(string, "00:02:00")
      }), {})
    }), {})
  })
  default = {}

  validation {
    condition     = startswith(var.health.path, "/")
    error_message = "health.path must start with '/' (for example, '/healthz' or '/readyz')."
  }

  validation {
    condition     = var.health.eviction_time_in_min >= 2 && var.health.eviction_time_in_min <= 10
    error_message = "health.eviction_time_in_min must be between 2 and 10 minutes (Azure App Service platform constraint)."
  }

  validation {
    condition     = var.health.startup_time_limit_seconds >= 30 && var.health.startup_time_limit_seconds <= 1800
    error_message = "health.startup_time_limit_seconds must be between 30 and 1800 seconds."
  }
}

# -----------------------------------------------------------------------------
# Rollouts & Deployment Slots
# -----------------------------------------------------------------------------

variable "rollout" {
  description = <<-EOT
    Safe deployment and release rollout configuration.
    Provisions a pre-production `staging` deployment slot matching production configuration, wires zero-downtime swap warmup probes
    automatically to `health.path`, disables legacy SCM basic-auth publishing in favor of Entra OIDC / Managed Identity,
    and pins slot-specific settings so slot swaps never leak staging configuration into production.
  EOT

  type = object({
    staging_slot_enabled                = optional(bool, true)
    auto_swap_enabled                   = optional(bool, false)
    basic_auth_publishing_enabled       = optional(bool, false)
    staging_image_tag                   = optional(string)
    warmup_ping_path                    = optional(string)
    warmup_expected_statuses            = optional(string, "200,204")
    staging_app_settings                = optional(map(string), {})
    slot_sticky_app_setting_names       = optional(list(string), [])
    slot_sticky_connection_string_names = optional(list(string), [])
  })
  default = {}

  validation {
    condition = (
      !var.rollout.staging_slot_enabled ||
      var.capacity.existing_service_plan_id != null ||
      !contains(["B1", "B2", "B3"], var.capacity.sku_name)
    )
    error_message = "Deployment slots require Standard, Premium, or Isolated App Service SKUs. Either upgrade capacity.sku_name or set rollout.staging_slot_enabled = false."
  }

  validation {
    condition     = !var.rollout.auto_swap_enabled || var.rollout.staging_slot_enabled
    error_message = "rollout.auto_swap_enabled requires rollout.staging_slot_enabled to be true."
  }

  validation {
    condition     = var.rollout.warmup_ping_path == null || startswith(coalesce(var.rollout.warmup_ping_path, "/"), "/")
    error_message = "rollout.warmup_ping_path must start with '/' when specified."
  }
}

# -----------------------------------------------------------------------------
# Observability: Logs, Metrics, Tracing & Golden-Signal Alerts
# -----------------------------------------------------------------------------

variable "observability" {
  description = <<-EOT
    End-to-end observability and SRE alerting configuration.
    Supports either attaching to shared platform Log Analytics / Application Insights resources or provisioning dedicated ones,
    streams all App Service logs (including container stdout/stderr) and metrics, injects OpenTelemetry + App Insights settings,
    and provisions Azure Monitor metric alerts for 5xx errors, latency, health probe degradation, and compute saturation.
  EOT

  type = object({
    existing_log_analytics_workspace_id             = optional(string)
    log_retention_in_days                           = optional(number, 30)
    log_daily_quota_gb                              = optional(number)
    application_insights_enabled                    = optional(bool, true)
    existing_application_insights_connection_string = optional(string)
    application_insights_retention_in_days          = optional(number, 90)
    application_insights_sampling_percentage        = optional(number, 100)
    filesystem_http_log_retention_mb                = optional(number, 50)
    filesystem_http_log_retention_days              = optional(number, 3)
    application_log_level                           = optional(string, "Information")
    alerts_enabled                                  = optional(bool, true)
    action_group_ids                                = optional(list(string), [])
    http_5xx_threshold                              = optional(number, 25)
    response_time_seconds_threshold                 = optional(number, 2)
    health_check_status_threshold                   = optional(number, 100)
    cpu_percentage_alert_threshold                  = optional(number, 90)
    memory_percentage_alert_threshold               = optional(number, 90)
  })
  default = {}

  validation {
    condition     = var.observability.log_retention_in_days >= 30 && var.observability.log_retention_in_days <= 730
    error_message = "observability.log_retention_in_days must be between 30 and 730 days."
  }

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.observability.application_insights_retention_in_days)
    error_message = "observability.application_insights_retention_in_days must be one of 30, 60, 90, 120, 180, 270, 365, 550, or 730."
  }

  validation {
    condition     = var.observability.application_insights_sampling_percentage >= 0 && var.observability.application_insights_sampling_percentage <= 100
    error_message = "observability.application_insights_sampling_percentage must be between 0 and 100."
  }

  validation {
    condition     = contains(["Error", "Warning", "Information", "Verbose", "Off"], var.observability.application_log_level)
    error_message = "observability.application_log_level must be one of 'Error', 'Warning', 'Information', 'Verbose', or 'Off'."
  }

  validation {
    condition     = var.observability.filesystem_http_log_retention_mb >= 25 && var.observability.filesystem_http_log_retention_mb <= 100
    error_message = "observability.filesystem_http_log_retention_mb must be between 25 and 100 MB."
  }
}

# -----------------------------------------------------------------------------
# Networking, Ingress Filtering & Private Connectivity
# -----------------------------------------------------------------------------

variable "network" {
  description = <<-EOT
    Network isolation, outbound VNet integration, ingress allowlists, Private Endpoint connectivity, and CORS policy.
    When `vnet_integration_subnet_id` is supplied, all outbound traffic and container image pulls automatically route over the VNet.
  EOT

  type = object({
    public_network_access_enabled = optional(bool, true)
    vnet_integration_subnet_id    = optional(string)
    scm_use_main_ip_restriction   = optional(bool, true)

    ip_restrictions = optional(list(object({
      name                      = string
      priority                  = number
      action                    = optional(string, "Allow")
      ip_address                = optional(string)
      service_tag               = optional(string)
      virtual_network_subnet_id = optional(string)
      headers = optional(object({
        x_azure_fdid      = optional(list(string))
        x_fd_health_probe = optional(list(string))
        x_forwarded_for   = optional(list(string))
        x_forwarded_host  = optional(list(string))
      }))
    })), [])

    scm_ip_restrictions = optional(list(object({
      name                      = string
      priority                  = number
      action                    = optional(string, "Allow")
      ip_address                = optional(string)
      service_tag               = optional(string)
      virtual_network_subnet_id = optional(string)
    })), [])

    private_endpoint = optional(object({
      subnet_id            = string
      private_dns_zone_ids = optional(list(string), [])
    }))

    cors = optional(object({
      allowed_origins     = list(string)
      support_credentials = optional(bool, false)
    }))
  })
  default = {}

  validation {
    condition = alltrue([
      for r in var.network.ip_restrictions : (
        contains(["Allow", "Deny"], r.action) &&
        length([for s in [r.ip_address, r.service_tag, r.virtual_network_subnet_id] : s if s != null]) == 1
      )
    ])
    error_message = "Each entry in network.ip_restrictions must have action 'Allow' or 'Deny' and specify exactly one of ip_address, service_tag, or virtual_network_subnet_id."
  }

  validation {
    condition = alltrue([
      for r in var.network.scm_ip_restrictions : (
        contains(["Allow", "Deny"], r.action) &&
        length([for s in [r.ip_address, r.service_tag, r.virtual_network_subnet_id] : s if s != null]) == 1
      )
    ])
    error_message = "Each entry in network.scm_ip_restrictions must have action 'Allow' or 'Deny' and specify exactly one of ip_address, service_tag, or virtual_network_subnet_id."
  }
}

# -----------------------------------------------------------------------------
# Application Configuration, Identity & Secrets
# -----------------------------------------------------------------------------

variable "app_settings" {
  description = "Non-sensitive runtime environment variables injected into the service. Standard platform settings (port, warmup probes, telemetry) are managed automatically."
  type        = map(string)
  default     = {}
}

variable "key_vault_secrets" {
  description = "Map of environment variable names to Azure Key Vault Secret URIs (for example, 'https://kv.vault.azure.net/secrets/api-key'). Automatically formatted as '@Microsoft.KeyVault(SecretUri=...)' references."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for uri in values(var.key_vault_secrets) :
      startswith(uri, "https://") || startswith(uri, "@Microsoft.KeyVault(")
    ])
    error_message = "Values in key_vault_secrets must be HTTPS Key Vault secret URIs or '@Microsoft.KeyVault(...)' reference expressions."
  }
}

variable "key_vault_id" {
  description = "Optional Azure Key Vault resource ID. When specified, grants 'Key Vault Secrets User' RBAC access to the Web App (and staging slot) System-Assigned Managed Identity."
  type        = string
  default     = null
}

variable "key_vault_reference_identity_id" {
  description = "Optional User-Assigned Managed Identity resource ID used to resolve Key Vault secret references. Defaults to the Web App's System-Assigned Managed Identity when null."
  type        = string
  default     = null
}

variable "user_assigned_identity_ids" {
  description = "Optional list of User-Assigned Managed Identity resource IDs attached alongside the Web App's System-Assigned Managed Identity."
  type        = list(string)
  default     = []
}

variable "connection_strings" {
  description = "Optional map of named connection strings injected into the Web App (for example, PostgreSQL, SQLAzure, RedisCache, or Custom)."
  type = map(object({
    type        = optional(string, "Custom")
    value       = string
    slot_sticky = optional(bool, false)
  }))
  default   = {}
  sensitive = true
}

variable "container_registry_credentials" {
  description = "Optional basic-auth credentials for external private container registries that do not support Azure Managed Identity authentication."
  type = object({
    username = string
    password = string
  })
  default   = null
  sensitive = true
}

variable "tags" {
  description = "Additional Azure resource tags merged with the module's standard operational tags (service, environment, managed_by)."
  type        = map(string)
  default     = {}
}
