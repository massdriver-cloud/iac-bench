variable "name" {
  description = "Globally unique Linux web app name and the base name for supporting resources. Use 3-45 lowercase letters, numbers, or hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,43}[a-z0-9]$", var.name))
    error_message = "name must be 3-45 characters and contain only lowercase letters, numbers, and hyphens, starting and ending with an alphanumeric character."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create or reuse."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0 && length(var.resource_group_name) <= 90
    error_message = "resource_group_name must be non-empty and no more than 90 characters."
  }
}

variable "location" {
  description = "Azure region for the app and its supporting resources."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "container_image" {
  description = "Production container repository and tag (for example, my-api:1.4.2), without a registry URL or DOCKER| prefix."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.container_image)) > 0 && !can(regex("://", var.container_image)) && !startswith(var.container_image, "DOCKER|")
    error_message = "container_image must be a non-empty repository:tag value without a URL scheme or DOCKER| prefix."
  }
}

variable "create_resource_group" {
  description = "Create the resource group. Set false to deploy into an existing resource group."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Additional tags for all taggable resources. Module ownership tags are always retained."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "service_plan_sku_name" {
  description = "Dedicated Linux App Service plan SKU. The default P1v3 supports slots and autoscaling; Free/Shared SKUs are rejected."
  type        = string
  default     = "P1v3"
  nullable    = false

  validation {
    condition     = length(trimspace(var.service_plan_sku_name)) > 0 && !contains(["F1", "D1"], upper(var.service_plan_sku_name))
    error_message = "service_plan_sku_name must be a non-empty Basic, Standard, Premium, or Isolated SKU; Free and Shared are not supported."
  }
}

variable "capacity" {
  description = "Initial and autoscale-default instance count. The live plan count is subsequently owned by autoscaling."
  type        = number
  default     = 2
  nullable    = false

  validation {
    condition     = floor(var.capacity) == var.capacity && var.capacity >= 1 && var.capacity <= 30
    error_message = "capacity must be a whole number between 1 and 30."
  }
}

variable "zone_balancing_enabled" {
  description = "Spread plan instances across availability zones. Requires a supported region/SKU and at least three initial and minimum instances."
  type        = bool
  default     = false
  nullable    = false
}

variable "autoscale_enabled" {
  description = "Create CPU-based autoscale rules for the App Service plan."
  type        = bool
  default     = true
  nullable    = false
}

variable "autoscale_minimum_capacity" {
  description = "Minimum instance count when autoscaling."
  type        = number
  default     = 2
  nullable    = false

  validation {
    condition     = floor(var.autoscale_minimum_capacity) == var.autoscale_minimum_capacity && var.autoscale_minimum_capacity >= 1 && var.autoscale_minimum_capacity <= 30
    error_message = "autoscale_minimum_capacity must be a whole number between 1 and 30."
  }
}

variable "autoscale_maximum_capacity" {
  description = "Maximum instance count when autoscaling."
  type        = number
  default     = 5
  nullable    = false

  validation {
    condition     = floor(var.autoscale_maximum_capacity) == var.autoscale_maximum_capacity && var.autoscale_maximum_capacity >= 1 && var.autoscale_maximum_capacity <= 30
    error_message = "autoscale_maximum_capacity must be a whole number between 1 and 30."
  }
}

variable "autoscale_scale_out_cpu_percentage" {
  description = "Ten-minute average plan CPU percentage that adds one instance."
  type        = number
  default     = 70
  nullable    = false

  validation {
    condition     = var.autoscale_scale_out_cpu_percentage > 0 && var.autoscale_scale_out_cpu_percentage <= 100
    error_message = "autoscale_scale_out_cpu_percentage must be greater than 0 and at most 100."
  }
}

variable "autoscale_scale_in_cpu_percentage" {
  description = "Fifteen-minute average plan CPU percentage that removes one instance."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.autoscale_scale_in_cpu_percentage >= 0 && var.autoscale_scale_in_cpu_percentage < 100
    error_message = "autoscale_scale_in_cpu_percentage must be at least 0 and less than 100."
  }
}

variable "container_port" {
  description = "Port on which the container listens; exported to App Service as WEBSITES_PORT."
  type        = number
  default     = 8080
  nullable    = false

  validation {
    condition     = floor(var.container_port) == var.container_port && var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be a whole number between 1 and 65535."
  }
}

variable "container_start_time_limit" {
  description = "Seconds App Service waits for container startup before restarting it (230-1800)."
  type        = number
  default     = 600
  nullable    = false

  validation {
    condition     = floor(var.container_start_time_limit) == var.container_start_time_limit && var.container_start_time_limit >= 230 && var.container_start_time_limit <= 1800
    error_message = "container_start_time_limit must be a whole number between 230 and 1800."
  }
}

variable "container_start_command" {
  description = "Optional container startup command. Leave null to use the image entrypoint."
  type        = string
  default     = null
}

variable "container_registry_url" {
  description = "HTTPS registry endpoint. MCR is the default; use https://<registry>.azurecr.io for ACR."
  type        = string
  default     = "https://mcr.microsoft.com"
  nullable    = false

  validation {
    condition     = can(regex("^https://[^/]+", var.container_registry_url))
    error_message = "container_registry_url must be an HTTPS registry URL."
  }
}

variable "container_registry_username" {
  description = "Optional private-registry username. Supply container_registry_password as well; prefer ACR managed identity instead."
  type        = string
  default     = null
}

variable "container_registry_password" {
  description = "Optional private-registry password. It remains sensitive in OpenTofu output but is stored in state."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_registry_use_managed_identity" {
  description = "Pull from ACR with the module-created user-assigned identity instead of registry passwords."
  type        = bool
  default     = false
  nullable    = false
}

variable "container_registry_id" {
  description = "ACR resource ID on which the module grants AcrPull. Required when managed identity registry pull is enabled."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Extra production application settings. Module-managed health, container, and Application Insights settings take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
  sensitive   = true
}

variable "health_check_path" {
  description = "HTTP health endpoint returning a 2xx response without authentication. Used by App Service and the external availability test."
  type        = string
  default     = "/health"
  nullable    = false

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with /."
  }
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may remain unhealthy before App Service replaces it (2-10)."
  type        = number
  default     = 5
  nullable    = false

  validation {
    condition     = floor(var.health_check_eviction_time_in_min) == var.health_check_eviction_time_in_min && var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be a whole number between 2 and 10."
  }
}

variable "deployment_slot_enabled" {
  description = "Create a warm staging deployment slot. Requires a Standard, Premium, or Isolated plan."
  type        = bool
  default     = true
  nullable    = false
}

variable "deployment_slot_name" {
  description = "Name of the optional staging slot."
  type        = string
  default     = "staging"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,58}[A-Za-z0-9]$", var.deployment_slot_name)) && lower(var.deployment_slot_name) != "production"
    error_message = "deployment_slot_name must be 2-60 alphanumeric/hyphen characters and must not be production."
  }
}

variable "staging_container_image" {
  description = "Optional different image for the staging slot. Leave null to mirror container_image; update this first for a slot-based rollout."
  type        = string
  default     = null
}

variable "staging_app_settings" {
  description = "Extra or overridden application settings for staging, except module-managed settings."
  type        = map(string)
  default     = {}
  nullable    = false
  sensitive   = true
}

variable "sticky_app_setting_names" {
  description = "App setting names that stay with a slot during swaps (for example, ENVIRONMENT)."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "virtual_network_subnet_id" {
  description = "Optional delegated subnet ID for regional VNet integration. All outbound app traffic is routed through it when set."
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = "Allow public inbound access to the app and its slot. Disable for private-endpoint-only production APIs."
  type        = bool
  default     = true
  nullable    = false
}

variable "allowed_source_cidrs" {
  description = "Optional inbound CIDR allow list for both app and SCM. Empty permits all sources when public access is enabled."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for cidr in var.allowed_source_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every allowed_source_cidrs entry must be a valid CIDR."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Optional subnet ID for a production-app private endpoint. The subnet must not be delegated to App Service VNet integration."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "Optional private DNS zone IDs (normally privatelink.azurewebsites.net) linked to the private endpoint."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "log_analytics_workspace_id" {
  description = "Optional existing Log Analytics workspace ID. If null, the module creates a workspace."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Log Analytics and Application Insights retention in days."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.log_retention_days)
    error_message = "log_retention_days must be one of 30, 60, 90, 120, 180, 270, 365, 550, or 730."
  }
}

variable "log_daily_quota_gb" {
  description = "Optional daily ingestion cap for a module-created Log Analytics workspace, in GB. Null means no module-set cap."
  type        = number
  default     = null

  validation {
    condition     = var.log_daily_quota_gb == null || var.log_daily_quota_gb > 0
    error_message = "log_daily_quota_gb must be null or greater than zero."
  }
}

variable "application_insights_daily_cap_gb" {
  description = "Optional Application Insights daily data cap in GB. Null means no module-set cap."
  type        = number
  default     = null

  validation {
    condition     = var.application_insights_daily_cap_gb == null || var.application_insights_daily_cap_gb > 0
    error_message = "application_insights_daily_cap_gb must be null or greater than zero."
  }
}

variable "application_insights_sampling_percentage" {
  description = "Application Insights fixed sampling percentage. Use 100 to retain all telemetry."
  type        = number
  default     = 100
  nullable    = false

  validation {
    condition     = var.application_insights_sampling_percentage > 0 && var.application_insights_sampling_percentage <= 100
    error_message = "application_insights_sampling_percentage must be greater than 0 and at most 100."
  }
}

variable "availability_test_enabled" {
  description = "Create an Application Insights standard health test for unrestricted public apps and alert below the availability threshold."
  type        = bool
  default     = true
  nullable    = false
}

variable "availability_test_geo_locations" {
  description = "Application Insights availability-test location IDs."
  type        = list(string)
  default     = ["us-tx-sn1-azr", "emea-nl-ams-azr"]
  nullable    = false

  validation {
    condition     = length(var.availability_test_geo_locations) >= 1 && alltrue([for location in var.availability_test_geo_locations : length(trimspace(location)) > 0])
    error_message = "Provide at least one non-empty availability test location ID."
  }
}

variable "availability_alert_threshold" {
  description = "Percentage availability below which the 15-minute availability alert fires."
  type        = number
  default     = 95
  nullable    = false

  validation {
    condition     = var.availability_alert_threshold > 0 && var.availability_alert_threshold <= 100
    error_message = "availability_alert_threshold must be greater than 0 and at most 100."
  }
}

variable "alerts_enabled" {
  description = "Enable all metric alert rules. Set false to keep rules deployed but muted."
  type        = bool
  default     = true
  nullable    = false
}

variable "alert_email_receivers" {
  description = "SRE email addresses for metric-alert and autoscale notifications. An action group is created when non-empty."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for email in var.alert_email_receivers : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email))])
    error_message = "Every alert_email_receivers entry must be a valid email address."
  }
}

variable "alert_action_group_ids" {
  description = "Existing action group IDs to notify in addition to the optional module-created email action group."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "http_5xx_alert_threshold" {
  description = "Total production HTTP 5xx responses over five minutes that triggers an alert."
  type        = number
  default     = 10
  nullable    = false

  validation {
    condition     = var.http_5xx_alert_threshold >= 0
    error_message = "http_5xx_alert_threshold must be non-negative."
  }
}

variable "response_time_alert_threshold_seconds" {
  description = "Average production response time in seconds over 15 minutes that triggers an alert."
  type        = number
  default     = 10
  nullable    = false

  validation {
    condition     = var.response_time_alert_threshold_seconds > 0
    error_message = "response_time_alert_threshold_seconds must be greater than zero."
  }
}

variable "cpu_alert_threshold" {
  description = "Average plan CPU percentage over 15 minutes that triggers an alert."
  type        = number
  default     = 85
  nullable    = false

  validation {
    condition     = var.cpu_alert_threshold > 0 && var.cpu_alert_threshold <= 100
    error_message = "cpu_alert_threshold must be greater than 0 and at most 100."
  }
}

variable "memory_alert_threshold" {
  description = "Average plan memory percentage over 15 minutes that triggers an alert."
  type        = number
  default     = 90
  nullable    = false

  validation {
    condition     = var.memory_alert_threshold > 0 && var.memory_alert_threshold <= 100
    error_message = "memory_alert_threshold must be greater than 0 and at most 100."
  }
}
