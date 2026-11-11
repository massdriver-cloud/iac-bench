variable "name" {
  description = "Service name. Used for the Web App and as the prefix for supporting resources; must be globally unique for App Service."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-40 characters, contain only letters, numbers and hyphens, and start and end with a letter or number."
  }
}

variable "resource_group_name" {
  description = "Name of the existing resource group in which all resources are created."
  type        = string
  nullable    = false
}

variable "location" {
  description = "Azure region for the service and its supporting resources."
  type        = string
  nullable    = false
}

variable "container_image" {
  description = "Production container image, including a tag or digest (for example, myregistry.azurecr.io/orders:1.4.2)."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.container_image)) > 0
    error_message = "container_image must not be empty."
  }
}

variable "container_registry_url" {
  description = "Registry URL, including the https:// scheme."
  type        = string
  default     = "https://mcr.microsoft.com"

  validation {
    condition     = can(regex("^https://", var.container_registry_url))
    error_message = "container_registry_url must be an HTTPS URL."
  }
}

variable "container_registry_username" {
  description = "Optional registry username. Do not use when managed-identity registry pull is enabled."
  type        = string
  default     = null
}

variable "container_registry_password" {
  description = "Optional registry password. Prefer managed identity and container_registry_id for Azure Container Registry."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_registry_use_managed_identity" {
  description = "Use the Web App managed identity to pull the image. Required for private ACR pulls without stored credentials."
  type        = bool
  default     = false
}

variable "container_registry_managed_identity_client_id" {
  description = "Optional client ID of a user-assigned identity used for registry pulls. Leave null to use the system-assigned identity."
  type        = string
  default     = null
}

variable "container_registry_id" {
  description = "Optional ACR resource ID. When managed-identity pull is enabled, the module grants AcrPull to the production and staging identities at this scope."
  type        = string
  default     = null
}

variable "container_port" {
  description = "TCP port on which the container listens. Exposed to App Service through WEBSITES_PORT."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "container_start_time_limit" {
  description = "Maximum container startup time in seconds before App Service restarts the container."
  type        = number
  default     = 600

  validation {
    condition     = var.container_start_time_limit >= 30 && var.container_start_time_limit <= 1800
    error_message = "container_start_time_limit must be between 30 and 1800 seconds."
  }
}

variable "health_check_path" {
  description = "Unauthenticated HTTP health endpoint. It must return HTTP 200 and should not depend on downstream services."
  type        = string
  default     = "/health"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may remain unhealthy before App Service replaces it (2-10)."
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

variable "service_plan_sku_name" {
  description = "App Service plan SKU. The production defaults are tested with Premium v3; use a SKU that supports zones, slots and autoscale when those features are enabled."
  type        = string
  default     = "P1v3"
}

variable "zone_redundant" {
  description = "Balance plan instances across availability zones. Requires a supported region/SKU and at least three instances."
  type        = bool
  default     = true
}

variable "instance_count" {
  description = "Number of plan workers when autoscale_enabled is false."
  type        = number
  default     = 3

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 100
    error_message = "instance_count must be between 1 and 100."
  }
}

variable "autoscale_enabled" {
  description = "Enable CPU-based plan autoscaling. While enabled, Azure owns the current worker count and OpenTofu ignores autoscale-driven worker-count drift."
  type        = bool
  default     = true
}

variable "autoscale_min_capacity" {
  description = "Minimum autoscaled plan instance count. Must be at least three for a zone-redundant plan."
  type        = number
  default     = 3

  validation {
    condition     = var.autoscale_min_capacity >= 1 && var.autoscale_min_capacity <= 100
    error_message = "autoscale_min_capacity must be between 1 and 100."
  }
}

variable "autoscale_default_capacity" {
  description = "Initial/default autoscaled plan instance count."
  type        = number
  default     = 3

  validation {
    condition     = var.autoscale_default_capacity >= 1 && var.autoscale_default_capacity <= 100
    error_message = "autoscale_default_capacity must be between 1 and 100."
  }
}

variable "autoscale_max_capacity" {
  description = "Maximum autoscaled plan instance count."
  type        = number
  default     = 10

  validation {
    condition     = var.autoscale_max_capacity >= 1 && var.autoscale_max_capacity <= 100
    error_message = "autoscale_max_capacity must be between 1 and 100."
  }
}

variable "autoscale_scale_out_cpu_threshold" {
  description = "Ten-minute average plan CPU percentage that triggers adding one instance."
  type        = number
  default     = 70

  validation {
    condition     = var.autoscale_scale_out_cpu_threshold > 0 && var.autoscale_scale_out_cpu_threshold <= 100
    error_message = "autoscale_scale_out_cpu_threshold must be greater than 0 and at most 100."
  }
}

variable "autoscale_scale_in_cpu_threshold" {
  description = "Ten-minute average plan CPU percentage that triggers removing one instance."
  type        = number
  default     = 30

  validation {
    condition     = var.autoscale_scale_in_cpu_threshold >= 0 && var.autoscale_scale_in_cpu_threshold < 100
    error_message = "autoscale_scale_in_cpu_threshold must be at least 0 and less than 100."
  }
}

variable "autoscale_notification_emails" {
  description = "Optional email addresses notified when autoscale actions occur."
  type        = list(string)
  default     = []
}

variable "deployment_slot_enabled" {
  description = "Create a staging slot for candidate deployment, smoke tests and near-zero-downtime swaps."
  type        = bool
  default     = true
}

variable "deployment_slot_name" {
  description = "Name of the deployment slot."
  type        = string
  default     = "staging"

  validation {
    condition     = var.deployment_slot_name != "production" && can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$", var.deployment_slot_name))
    error_message = "deployment_slot_name must be 2-60 alphanumeric/hyphen characters, start and end alphanumeric, and must not be 'production'."
  }
}

variable "app_settings" {
  description = "Additional container environment variables/App Service settings. Values may be Key Vault references. This variable is sensitive; prefer references over plaintext secrets."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "sticky_app_setting_names" {
  description = "App setting names that remain with their slot during swaps (for example, ENVIRONMENT or slot-specific connection strings)."
  type        = list(string)
  default     = []
}

variable "user_assigned_identity_ids" {
  description = "Optional user-assigned managed identity resource IDs attached to both production and staging. A system-assigned identity is always enabled."
  type        = set(string)
  default     = []
}

variable "key_vault_reference_identity_id" {
  description = "Optional identity resource ID used to resolve Key Vault references in app settings. Leave null to use the system-assigned identity."
  type        = string
  default     = null
}

variable "vnet_integration_subnet_id" {
  description = "Optional delegated subnet ID for regional VNet integration (outbound traffic)."
  type        = string
  default     = null
}

variable "vnet_route_all_enabled" {
  description = "Route all outbound application traffic through VNet integration, rather than only RFC1918 traffic."
  type        = bool
  default     = true
}

variable "vnet_image_pull_enabled" {
  description = "Pull the container image through VNet integration. Requires vnet_integration_subnet_id."
  type        = bool
  default     = false
}

variable "private_endpoint_subnet_id" {
  description = "Optional subnet ID for a production Web App private endpoint (inbound traffic). When set, public access defaults to disabled."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "Private DNS zone IDs linked to the private endpoint, normally privatelink.azurewebsites.net."
  type        = list(string)
  default     = []
}

variable "public_network_access_enabled" {
  description = "Override public network access. Null automatically disables public access when a private endpoint is configured and enables it otherwise."
  type        = bool
  default     = null
  nullable    = true
}

variable "ip_restrictions" {
  description = "Ordered production/staging access rules. Set ip_restriction_default_action to Deny to make this an allow-list. SCM inherits these rules."
  type = list(object({
    name                      = string
    priority                  = number
    action                    = optional(string, "Allow")
    description               = optional(string)
    ip_address                = optional(string)
    service_tag               = optional(string)
    virtual_network_subnet_id = optional(string)
  }))
  default = []
}

variable "ip_restriction_default_action" {
  description = "Action when no IP restriction matches. Use Deny with an allow-list; public_network_access_enabled=false is preferred for private-only ingress."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.ip_restriction_default_action)
    error_message = "ip_restriction_default_action must be Allow or Deny."
  }
}

variable "log_analytics_workspace_id" {
  description = "Optional existing Log Analytics workspace ID. If omitted, the module creates a workspace."
  type        = string
  default     = null
}

variable "log_retention_in_days" {
  description = "Retention for a module-created Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_in_days >= 30 && var.log_retention_in_days <= 730
    error_message = "log_retention_in_days must be between 30 and 730."
  }
}

variable "log_daily_quota_gb" {
  description = "Optional daily ingestion quota in GB for a module-created workspace. Null means no module-set quota."
  type        = number
  default     = null
}

variable "application_log_level" {
  description = "Application filesystem log level. Persistent logs and metrics are also sent to Log Analytics."
  type        = string
  default     = "Information"

  validation {
    condition     = contains(["Off", "Error", "Warning", "Information", "Verbose"], var.application_log_level)
    error_message = "application_log_level must be Off, Error, Warning, Information or Verbose."
  }
}

variable "diagnostic_log_categories" {
  description = "App Service log categories sent to Log Analytics for production and staging."
  type        = list(string)
  default = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServicePlatformLogs"
  ]
}

variable "application_insights_sampling_percentage" {
  description = "Application Insights telemetry sampling percentage. Use 100 for low-volume services and tune for high-volume services."
  type        = number
  default     = 100

  validation {
    condition     = var.application_insights_sampling_percentage > 0 && var.application_insights_sampling_percentage <= 100
    error_message = "application_insights_sampling_percentage must be greater than 0 and at most 100."
  }
}

variable "alerts_enabled" {
  description = "Create baseline health, HTTP 5xx, sustained CPU and (when public) external availability alerts."
  type        = bool
  default     = true
}

variable "action_group_id" {
  description = "Optional existing action group used by all alerts and the external availability test. Takes precedence over alert_email_receivers."
  type        = string
  default     = null
}

variable "alert_email_receivers" {
  description = "Email receivers for a module-created alert action group. Ignored when action_group_id is supplied."
  type = list(object({
    name          = string
    email_address = string
  }))
  default = []
}

variable "http_5xx_alert_threshold" {
  description = "Total production HTTP 5xx responses over five minutes that raises a severity-2 alert."
  type        = number
  default     = 10

  validation {
    condition     = var.http_5xx_alert_threshold >= 0
    error_message = "http_5xx_alert_threshold must be non-negative."
  }
}

variable "cpu_alert_threshold" {
  description = "Fifteen-minute average plan CPU percentage that raises a severity-2 alert."
  type        = number
  default     = 85

  validation {
    condition     = var.cpu_alert_threshold > 0 && var.cpu_alert_threshold <= 100
    error_message = "cpu_alert_threshold must be greater than 0 and at most 100."
  }
}

variable "availability_test_enabled" {
  description = "Run an external Application Insights standard test against health_check_path when public access is enabled."
  type        = bool
  default     = true
}

variable "availability_test_geo_locations" {
  description = "At least two Application Insights standard-test population location IDs."
  type        = list(string)
  default     = ["us-va-ash-azr", "us-fl-mia-edge"]

  validation {
    condition     = length(var.availability_test_geo_locations) >= 2
    error_message = "availability_test_geo_locations must contain at least two locations."
  }
}

variable "availability_alert_threshold" {
  description = "Five-minute average availability percentage below which a severity-1 alert fires."
  type        = number
  default     = 99

  validation {
    condition     = var.availability_alert_threshold > 0 && var.availability_alert_threshold <= 100
    error_message = "availability_alert_threshold must be greater than 0 and at most 100."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource. These override the module's default tags on key collisions."
  type        = map(string)
  default     = {}
}
