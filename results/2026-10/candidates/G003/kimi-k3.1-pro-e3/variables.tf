variable "name" {
  description = "Service name. It is used for the globally unique web app name and as the prefix for all other resource names. Use 2-36 lowercase alphanumeric characters or hyphens."
  type        = string

  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 36 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be 2-36 lowercase alphanumeric characters or hyphens, and must start and end with an alphanumeric character."
  }
}

variable "location" {
  description = "Azure region. When an existing resource group is used, the resource group's region takes precedence."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "container_image" {
  description = "Production container image, including its tag or digest (for example, myregistry.azurecr.io/orders:1.4.2). Prefer an immutable tag or digest."
  type        = string

  validation {
    condition     = length(trimspace(var.container_image)) > 0
    error_message = "container_image must not be empty."
  }
}

variable "resource_group_name" {
  description = "Resource group name. Defaults to <name>-rg. Set create_resource_group to false to use an existing group."
  type        = string
  default     = null

  validation {
    condition     = var.resource_group_name == null || length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty when supplied."
  }
}

variable "create_resource_group" {
  description = "Create the resource group as part of the service stack. If false, the named resource group must already exist."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags applied to every taggable resource. These override the module's default tag values on key collisions."
  type        = map(string)
  default     = {}
}

variable "plan_sku_name" {
  description = "App Service plan SKU. The default P1v3 supports staging slots and production workloads. A Standard or Premium SKU is required when deployment_slot_enabled is true."
  type        = string
  default     = "P1v3"

  validation {
    condition     = length(trimspace(var.plan_sku_name)) > 0
    error_message = "plan_sku_name must not be empty."
  }
}

variable "plan_worker_count" {
  description = "Number of plan instances when autoscale_enabled is false. Ignored for an autoscaled plan, whose initial size is autoscale_default_capacity."
  type        = number
  default     = 2

  validation {
    condition     = floor(var.plan_worker_count) == var.plan_worker_count && var.plan_worker_count >= 1 && var.plan_worker_count <= 100
    error_message = "plan_worker_count must be an integer between 1 and 100."
  }
}

variable "zone_balancing_enabled" {
  description = "Enable zone balancing for the App Service plan. The selected SKU and region must support it, and at least three instances (including the autoscale minimum) are required."
  type        = bool
  default     = false
}

variable "autoscale_enabled" {
  description = "Manage a CPU- and memory-based Azure Monitor autoscale profile for the App Service plan."
  type        = bool
  default     = true
}

variable "autoscale_minimum_capacity" {
  description = "Minimum plan instance count. Keep this at three or more when zone balancing is enabled."
  type        = number
  default     = 2

  validation {
    condition     = floor(var.autoscale_minimum_capacity) == var.autoscale_minimum_capacity && var.autoscale_minimum_capacity >= 1 && var.autoscale_minimum_capacity <= 100
    error_message = "autoscale_minimum_capacity must be an integer between 1 and 100."
  }
}

variable "autoscale_default_capacity" {
  description = "Initial and fallback plan instance count; it must be between the minimum and maximum capacities."
  type        = number
  default     = 2

  validation {
    condition     = floor(var.autoscale_default_capacity) == var.autoscale_default_capacity && var.autoscale_default_capacity >= 1 && var.autoscale_default_capacity <= 100
    error_message = "autoscale_default_capacity must be an integer between 1 and 100."
  }
}

variable "autoscale_maximum_capacity" {
  description = "Maximum plan instance count."
  type        = number
  default     = 6

  validation {
    condition     = floor(var.autoscale_maximum_capacity) == var.autoscale_maximum_capacity && var.autoscale_maximum_capacity >= 1 && var.autoscale_maximum_capacity <= 100
    error_message = "autoscale_maximum_capacity must be an integer between 1 and 100."
  }
}

variable "autoscale_cpu_scale_out_threshold" {
  description = "Five-minute average CPU percentage that triggers adding an instance."
  type        = number
  default     = 70

  validation {
    condition     = var.autoscale_cpu_scale_out_threshold > 0 && var.autoscale_cpu_scale_out_threshold <= 100
    error_message = "autoscale_cpu_scale_out_threshold must be greater than 0 and at most 100."
  }
}

variable "autoscale_memory_scale_out_threshold" {
  description = "Five-minute average memory percentage that triggers adding an instance."
  type        = number
  default     = 75

  validation {
    condition     = var.autoscale_memory_scale_out_threshold > 0 && var.autoscale_memory_scale_out_threshold <= 100
    error_message = "autoscale_memory_scale_out_threshold must be greater than 0 and at most 100."
  }
}

variable "autoscale_cpu_scale_in_threshold" {
  description = "Five-minute average CPU percentage used by the conservative scale-in rule."
  type        = number
  default     = 30

  validation {
    condition     = var.autoscale_cpu_scale_in_threshold >= 0 && var.autoscale_cpu_scale_in_threshold < 100
    error_message = "autoscale_cpu_scale_in_threshold must be at least 0 and less than 100."
  }
}

variable "autoscale_memory_scale_in_threshold" {
  description = "Five-minute average memory percentage used by the conservative scale-in rule."
  type        = number
  default     = 50

  validation {
    condition     = var.autoscale_memory_scale_in_threshold >= 0 && var.autoscale_memory_scale_in_threshold < 100
    error_message = "autoscale_memory_scale_in_threshold must be at least 0 and less than 100."
  }
}

variable "autoscale_notification_emails" {
  description = "Email addresses notified when autoscale actions occur."
  type        = list(string)
  default     = []
}

variable "deployment_slot_enabled" {
  description = "Create a staging deployment slot for controlled swaps. Requires a Standard or Premium App Service SKU."
  type        = bool
  default     = true
}

variable "deployment_slot_name" {
  description = "Deployment slot name, up to 15 characters."
  type        = string
  default     = "staging"

  validation {
    condition     = length(var.deployment_slot_name) >= 1 && length(var.deployment_slot_name) <= 15 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.deployment_slot_name))
    error_message = "deployment_slot_name must be 1-15 lowercase alphanumeric characters or hyphens, and start and end with an alphanumeric character."
  }
}

variable "staging_container_image" {
  description = "Optional image used only by the staging slot. Leave null to mirror container_image. During a rollout, set the new image here first, test staging, swap, and then promote it to container_image."
  type        = string
  default     = null

  validation {
    condition     = var.staging_container_image == null || length(trimspace(var.staging_container_image)) > 0
    error_message = "staging_container_image must not be empty when supplied."
  }
}

variable "container_port" {
  description = "TCP port on which the container listens. App Service routes HTTP traffic to this port."
  type        = number
  default     = 8080

  validation {
    condition     = floor(var.container_port) == var.container_port && var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "container_start_time_limit_seconds" {
  description = "Maximum time App Service waits for the container to start before restarting it."
  type        = number
  default     = 600

  validation {
    condition     = floor(var.container_start_time_limit_seconds) == var.container_start_time_limit_seconds && var.container_start_time_limit_seconds >= 30 && var.container_start_time_limit_seconds <= 1800
    error_message = "container_start_time_limit_seconds must be an integer between 30 and 1800."
  }
}

variable "app_command_line" {
  description = "Optional startup command that overrides the container image's default command."
  type        = string
  default     = null
}

variable "container_registry_url" {
  description = "Container registry URL, for example https://myregistry.azurecr.io. Leave null for the provider's Docker Hub default."
  type        = string
  default     = null
}

variable "container_registry_use_managed_identity" {
  description = "Use the module-managed user-assigned identity for registry pulls. This is ignored when a registry username is supplied."
  type        = bool
  default     = true
}

variable "container_registry_id" {
  description = "Optional Azure Container Registry resource ID. When managed-identity pulls are active, the module grants the app identity AcrPull at this scope."
  type        = string
  default     = null
}

variable "container_registry_username" {
  description = "Optional registry username. Supplying credentials disables managed-identity registry authentication. Prefer managed identity for ACR."
  type        = string
  default     = null
}

variable "container_registry_password" {
  description = "Password for container_registry_username. This value is sensitive and remains in the OpenTofu state."
  type        = string
  sensitive   = true
  default     = null
}

variable "app_settings" {
  description = "Additional production app settings. Use Key Vault references rather than plaintext secrets. Module-managed App Service and Application Insights settings take precedence."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "staging_app_settings" {
  description = "Additional or overridden app settings for the staging slot. List names in sticky_app_setting_names when values must stay with a slot during swaps."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "sticky_app_setting_names" {
  description = "App setting names that remain attached to their current slot during a swap (for example, a slot-specific environment name)."
  type        = list(string)
  default     = []
}

variable "health_check_path" {
  description = "HTTP path used by App Service health checks. The endpoint should return a successful status only when the instance is ready for traffic. Set null to disable health checks."
  type        = string
  default     = "/health"

  validation {
    condition     = var.health_check_path == null || can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/' or be null."
  }
}

variable "health_check_eviction_time_in_minutes" {
  description = "Time an instance may remain unhealthy before App Service replaces it."
  type        = number
  default     = 10

  validation {
    condition     = floor(var.health_check_eviction_time_in_minutes) == var.health_check_eviction_time_in_minutes && var.health_check_eviction_time_in_minutes >= 2 && var.health_check_eviction_time_in_minutes <= 10
    error_message = "health_check_eviction_time_in_minutes must be an integer between 2 and 10."
  }
}

variable "app_service_log_level" {
  description = "Application log level for the short-lived App Service filesystem log."
  type        = string
  default     = "Information"

  validation {
    condition     = contains(["Error", "Information", "Off", "Verbose", "Warning"], var.app_service_log_level)
    error_message = "app_service_log_level must be Error, Information, Off, Verbose, or Warning."
  }
}

variable "log_retention_days" {
  description = "Log Analytics workspace data retention in days."
  type        = number
  default     = 30

  validation {
    condition     = floor(var.log_retention_days) == var.log_retention_days && var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be an integer between 30 and 730."
  }
}

variable "log_daily_quota_gb" {
  description = "Optional Log Analytics daily ingestion cap in GB. Null leaves the workspace uncapped."
  type        = number
  default     = null

  validation {
    condition     = var.log_daily_quota_gb == null || var.log_daily_quota_gb > 0
    error_message = "log_daily_quota_gb must be greater than zero when supplied."
  }
}

variable "application_insights_sampling_percentage" {
  description = "Application Insights adaptive/fixed-rate sampling percentage configured on the Application Insights resource."
  type        = number
  default     = 100

  validation {
    condition     = var.application_insights_sampling_percentage >= 0 && var.application_insights_sampling_percentage <= 100
    error_message = "application_insights_sampling_percentage must be between 0 and 100."
  }
}

variable "diagnostic_log_categories" {
  description = "App Service log categories exported to Log Analytics for both production and staging."
  type        = list(string)
  default = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServicePlatformLogs",
  ]
}

variable "enable_metric_alerts" {
  description = "Create the standard HTTP 5xx, response-time, and health-check metric alerts and their action group."
  type        = bool
  default     = true
}

variable "alert_email_receivers" {
  description = "Email receivers attached to the alert action group. With no receivers, alerts are still visible in Azure Monitor."
  type = list(object({
    name                    = string
    email_address           = string
    use_common_alert_schema = optional(bool, true)
  }))
  default = []
}

variable "http_5xx_alert_threshold" {
  description = "Total production HTTP 5xx responses in five minutes that triggers the severity-2 alert."
  type        = number
  default     = 5

  validation {
    condition     = var.http_5xx_alert_threshold >= 0
    error_message = "http_5xx_alert_threshold must be non-negative."
  }
}

variable "response_time_alert_threshold_seconds" {
  description = "Five-minute average production response time, in seconds, that triggers the severity-3 alert."
  type        = number
  default     = 5

  validation {
    condition     = var.response_time_alert_threshold_seconds > 0
    error_message = "response_time_alert_threshold_seconds must be greater than zero."
  }
}

variable "virtual_network_subnet_id" {
  description = "Optional delegated subnet resource ID for regional VNet integration (outbound connectivity). The same integration is applied to production and staging."
  type        = string
  default     = null
}

variable "vnet_route_all_enabled" {
  description = "Route all outbound application traffic through the VNet integration rather than only RFC1918 traffic."
  type        = bool
  default     = false
}

variable "vnet_image_pull_enabled" {
  description = "Pull the application image through the VNet integration, for registries reachable only from that VNet."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow public inbound access to production and staging. If disabled, provide private inbound connectivity separately."
  type        = bool
  default     = true
}

variable "ip_restriction_default_action" {
  description = "Default action when no inbound IP restriction matches. Use Deny together with at least one Allow rule for a restricted service."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.ip_restriction_default_action)
    error_message = "ip_restriction_default_action must be Allow or Deny."
  }
}

variable "ip_restrictions" {
  description = "Ordered inbound access rules. Each rule must specify exactly one of ip_address, service_tag, or virtual_network_subnet_id. The same rules protect the SCM endpoint."
  type = list(object({
    name                      = string
    priority                  = number
    action                    = optional(string, "Allow")
    ip_address                = optional(string)
    service_tag               = optional(string)
    virtual_network_subnet_id = optional(string)
    description               = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for rule in var.ip_restrictions : contains(["Allow", "Deny"], rule.action) && rule.priority >= 100 && rule.priority <= 65000])
    error_message = "Each IP restriction must have action Allow or Deny and a priority between 100 and 65000."
  }
}

variable "cors_allowed_origins" {
  description = "Allowed browser origins for App Service CORS. Empty disables the module-managed CORS block; non-browser API clients are unaffected."
  type        = list(string)
  default     = []
}

variable "cors_support_credentials" {
  description = "Whether App Service CORS responses allow credentials. Do not combine this with a wildcard origin."
  type        = bool
  default     = false
}
