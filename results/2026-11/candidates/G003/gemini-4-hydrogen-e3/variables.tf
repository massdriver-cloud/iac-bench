variable "service_name" {
  description = "Canonical name of the HTTP service (lowercase alphanumeric and hyphens, e.g. 'orders-api')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-40 characters, lowercase alphanumeric or hyphens, starting and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g. 'dev', 'staging', 'prod')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,16}$", var.environment))
    error_message = "environment must be 2-16 characters, lowercase alphanumeric or hyphens."
  }
}

variable "location" {
  description = "Azure region for all service resources (e.g. 'eastus2', 'westeurope')."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must be a non-empty Azure region name."
  }
}

variable "container_image" {
  description = "Container image name and tag to deploy to production (e.g. 'myorg/orders-api:1.4.2' or 'mcr.microsoft.com/azuredocs/aci-helloworld:latest')."
  type        = string

  validation {
    condition     = length(trimspace(var.container_image)) > 0 && !startswith(var.container_image, "https://") && !startswith(var.container_image, "http://")
    error_message = "container_image must be an image reference (e.g. 'repo/image:tag') without an http(s):// scheme; configure registry URL via var.container_registry.url."
  }
}

variable "create_resource_group" {
  description = "Whether to create a dedicated Resource Group for this service. Set to false to deploy into an existing Resource Group named by resource_group_name."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Name of the Resource Group. Defaults to 'rg-<service_name>-<environment>' when create_resource_group is true; required when create_resource_group is false."
  type        = string
  default     = null

  validation {
    condition     = var.resource_group_name == null || length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must be null or a non-empty string."
  }
}

variable "container_registry" {
  description = "Container registry configuration for pulling images. Supply password via container_registry_password when not using managed identity."
  type = object({
    url                        = optional(string, "https://index.docker.io")
    use_managed_identity       = optional(bool, false)
    managed_identity_id        = optional(string, null)
    managed_identity_client_id = optional(string, null)
    acr_id                     = optional(string, null)
    username                   = optional(string, null)
  })
  default = {}

  validation {
    condition     = var.container_registry.url == null || can(regex("^https://", var.container_registry.url))
    error_message = "container_registry.url must start with 'https://'."
  }
}

variable "container_registry_password" {
  description = "Password or pull token for container_registry.username when not using managed identity."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_port" {
  description = "TCP port the containerized HTTP API listens on (mapped to WEBSITES_PORT)."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "container_command" {
  description = "Optional startup command override for the container."
  type        = string
  default     = null
}

variable "container_start_timeout_seconds" {
  description = "Maximum seconds App Service waits for the container to start listening on container_port."
  type        = number
  default     = 230

  validation {
    condition     = var.container_start_timeout_seconds >= 60 && var.container_start_timeout_seconds <= 1800
    error_message = "container_start_timeout_seconds must be between 60 and 1800."
  }
}

variable "capacity" {
  description = "SRE capacity and scaling configuration. 'profile' maps to standard App Service SKUs ('dev'->B1, 'basic'->S1, 'standard'->P1v3, 'compute'->P2v3, 'high_compute'->P3v3, 'memory'->P1mv3); 'sku_name' overrides the profile."
  type = object({
    profile                      = optional(string, "standard")
    sku_name                     = optional(string, null)
    existing_service_plan_id     = optional(string, null)
    min_instances                = optional(number, 2)
    max_instances                = optional(number, 5)
    always_on                    = optional(bool, true)
    autoscale_cpu_out_percent    = optional(number, 70)
    autoscale_cpu_in_percent     = optional(number, 30)
    autoscale_memory_out_percent = optional(number, 80)
  })
  default = {}

  validation {
    condition     = contains(["dev", "basic", "standard", "compute", "high_compute", "memory"], var.capacity.profile)
    error_message = "capacity.profile must be one of: dev, basic, standard, compute, high_compute, memory."
  }

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances
    error_message = "capacity.min_instances must be >= 1 and capacity.max_instances must be >= min_instances."
  }

  validation {
    condition     = var.capacity.autoscale_cpu_in_percent < var.capacity.autoscale_cpu_out_percent && var.capacity.autoscale_cpu_in_percent >= 5 && var.capacity.autoscale_cpu_out_percent <= 95
    error_message = "autoscale_cpu_in_percent must be less than autoscale_cpu_out_percent (within 5-95)."
  }
}

variable "availability" {
  description = "High-availability, network exposure, and TLS hardening settings."
  type = object({
    zone_redundant                = optional(bool, false)
    https_only                    = optional(bool, true)
    minimum_tls_version           = optional(string, "1.2")
    http2_enabled                 = optional(bool, true)
    client_affinity_enabled       = optional(bool, false)
    public_network_access_enabled = optional(bool, true)
    vnet_integration_subnet_id    = optional(string, null)
    vnet_route_all_enabled        = optional(bool, true)
    ip_restrictions = optional(list(object({
      name                      = string
      priority                  = number
      action                    = optional(string, "Allow")
      ip_address                = optional(string, null)
      service_tag               = optional(string, null)
      virtual_network_subnet_id = optional(string, null)
    })), [])
    ip_restriction_default_action = optional(string, "Allow")
    cors = optional(object({
      allowed_origins     = list(string)
      support_credentials = optional(bool, false)
    }), null)
  })
  default = {}

  validation {
    condition     = contains(["1.2", "1.3"], var.availability.minimum_tls_version)
    error_message = "availability.minimum_tls_version must be '1.2' or '1.3'."
  }

  validation {
    condition     = contains(["Allow", "Deny"], var.availability.ip_restriction_default_action)
    error_message = "availability.ip_restriction_default_action must be 'Allow' or 'Deny'."
  }
}

variable "health_check" {
  description = "HTTP health probe and eviction settings for automatic unhealthy instance replacement."
  type = object({
    path                  = optional(string, "/healthz")
    eviction_time_minutes = optional(number, 5)
    max_ping_failures     = optional(number, 3)
  })
  default = {}

  validation {
    condition     = var.health_check.path == null || startswith(var.health_check.path, "/")
    error_message = "health_check.path must be null or start with '/'."
  }

  validation {
    condition     = var.health_check.eviction_time_minutes >= 2 && var.health_check.eviction_time_minutes <= 10
    error_message = "health_check.eviction_time_minutes must be between 2 and 10."
  }
}

variable "rollout" {
  description = "Zero-downtime rollout configuration using deployment slots, warmup probes, and graceful shutdown."
  type = object({
    enable_staging_slot       = optional(bool, null)
    staging_container_image   = optional(string, null)
    staging_app_settings      = optional(map(string), {})
    warmup_ping_statuses      = optional(string, "200,204")
    graceful_shutdown_seconds = optional(number, 30)
    sticky_app_setting_names  = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = var.rollout.graceful_shutdown_seconds >= 5 && var.rollout.graceful_shutdown_seconds <= 600
    error_message = "rollout.graceful_shutdown_seconds must be between 5 and 600."
  }
}

variable "observability" {
  description = "Logging, Application Insights APM, diagnostic routing, and SRE metric alerting."
  type = object({
    enabled                     = optional(bool, true)
    log_analytics_workspace_id  = optional(string, null)
    retention_days              = optional(number, 30)
    enable_application_insights = optional(bool, true)
    enable_diagnostic_settings  = optional(bool, true)
    application_logs_level      = optional(string, "Information")
    enable_alerts               = optional(bool, true)
    alert_action_group_ids      = optional(list(string), [])
    alert_thresholds = optional(object({
      http_5xx_count  = optional(number, 10)
      latency_seconds = optional(number, 2.0)
      cpu_percent     = optional(number, 85)
      memory_percent  = optional(number, 85)
    }), {})
  })
  default = {}

  validation {
    condition     = contains(["Off", "Error", "Warning", "Information", "Verbose"], var.observability.application_logs_level)
    error_message = "observability.application_logs_level must be one of: Off, Error, Warning, Information, Verbose."
  }

  validation {
    condition     = var.observability.retention_days >= 30 && var.observability.retention_days <= 730
    error_message = "observability.retention_days must be between 30 and 730."
  }
}

variable "app_settings" {
  description = "Non-sensitive environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "secret_app_settings" {
  description = "Sensitive environment variables (e.g. Key Vault references or secrets) injected into the container."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "connection_strings" {
  description = "Optional App Service connection strings."
  type = map(object({
    type  = string
    value = string
  }))
  default   = {}
  sensitive = true
}

variable "user_assigned_identity_ids" {
  description = "Optional list of User Assigned Managed Identity resource IDs to attach in addition to the System Assigned identity."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional Azure resource tags merged onto all module resources."
  type        = map(string)
  default     = {}
}
