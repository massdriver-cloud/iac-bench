###############################################################################
# Core Service & Deployment Identification
###############################################################################

variable "service_name" {
  type        = string
  description = "The logical name of the HTTP API service (e.g., 'orders-api', 'auth-service'). Used in resource naming."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the target Azure Resource Group where resources will be provisioned."
}

variable "location" {
  type        = string
  description = "The Azure region for all deployed resources (e.g., 'eastus', 'westeurope')."
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Deployment environment name (e.g., 'prod', 'staging', 'dev')."
}

variable "name_prefix" {
  type        = string
  default     = ""
  description = "Optional prefix prepended to all resource names (e.g., 'corp')."
}

variable "custom_app_name" {
  type        = string
  default     = null
  description = "Optional explicit App Service name. Overrides standard naming convention if supplied."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Resource tags applied to all provisioned Azure resources."
}

###############################################################################
# Container Configuration
###############################################################################

variable "container_image" {
  type        = string
  description = "Full container image reference to deploy (e.g., 'mcr.microsoft.com/azuredocs/aci-helloworld:latest' or 'myacr.azurecr.io/api:v1.0.0')."
}

variable "container_port" {
  type        = number
  default     = 8080
  description = "The internal listening port of the container HTTP server. Configures WEBSITES_PORT."
}

variable "container_registry_url" {
  type        = string
  default     = null
  description = "URL of private container registry (e.g., 'https://myregistry.azurecr.io'). Leave null for Docker Hub or public registries."
}

variable "container_registry_username" {
  type        = string
  default     = null
  description = "Username for authenticating against private container registry."
}

variable "container_registry_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Password or token for authenticating against private container registry."
}

variable "container_registry_use_managed_identity" {
  type        = bool
  default     = false
  description = "Configure App Service to pull container images using its managed identity (AcrPull)."
}

variable "docker_enable_ci" {
  type        = bool
  default     = false
  description = "Enable continuous deployment webhook triggers for the container."
}

###############################################################################
# Capacity & App Service Plan
###############################################################################

variable "service_plan_id" {
  type        = string
  default     = null
  description = "Optional existing App Service Plan ID to host this service. If null, a dedicated Linux Service Plan is created."
}

variable "service_plan_name" {
  type        = string
  default     = null
  description = "Optional custom name for the App Service Plan when created by this module."
}

variable "sku_name" {
  type        = string
  default     = "P1v3"
  description = "App Service Plan SKU tier and size (e.g., 'P1v3', 'P2v3', 'B1', 'S1'). Recommended: Premium v3 for production workloads."
}

variable "zone_balancing_enabled" {
  type        = bool
  default     = false
  description = "Enable zone balancing for multi-AZ high availability. Requires Premium tier and capacity >= 3."
}

variable "capacity" {
  type = object({
    min     = optional(number, 2)
    max     = optional(number, 10)
    default = optional(number, 2)
  })
  default = {
    min     = 2
    max     = 10
    default = 2
  }
  description = "Capacity scaling bounds: minimum, maximum, and default worker instance count."

  validation {
    condition     = var.capacity.min >= 1 && var.capacity.max >= var.capacity.min && var.capacity.default >= var.capacity.min && var.capacity.default <= var.capacity.max
    error_message = "capacity.min must be >= 1, capacity.max must be >= capacity.min, and capacity.default must be between min and max."
  }
}

variable "enable_autoscaling" {
  type        = bool
  default     = true
  description = "Enable metric-based autoscaling for the App Service Plan."
}

variable "autoscale_rules" {
  type = object({
    cpu_scale_out_threshold    = optional(number, 70)
    cpu_scale_in_threshold     = optional(number, 30)
    memory_scale_out_threshold = optional(number, 80)
    memory_scale_in_threshold  = optional(number, 40)
    cooldown_minutes           = optional(number, 5)
  })
  default = {
    cpu_scale_out_threshold    = 70
    cpu_scale_in_threshold     = 30
    memory_scale_out_threshold = 80
    memory_scale_in_threshold  = 40
    cooldown_minutes           = 5
  }
  description = "Metric thresholds and cooldown duration for CPU and Memory horizontal autoscaling rules."
}

###############################################################################
# Availability & Health
###############################################################################

variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "HTTP endpoint path probed by Azure App Service to determine instance health and route traffic."
}

variable "health_check_eviction_time_in_min" {
  type        = number
  default     = 5
  description = "Minutes an unhealthy instance is allowed to fail probes before being evicted from routing (2-10 minutes)."

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10 minutes."
  }
}

variable "minimum_tls_version" {
  type        = string
  default     = "1.2"
  description = "Minimum TLS cipher version enforced for incoming connections ('1.2' or '1.3')."
}

variable "http2_enabled" {
  type        = bool
  default     = true
  description = "Enable HTTP/2 protocol support for client connections."
}

###############################################################################
# Rollouts & Deployment Slots
###############################################################################

variable "enable_staging_slot" {
  type        = bool
  default     = true
  description = "Provision a staging deployment slot for zero-downtime container rollouts and warmup validation."
}

variable "staging_slot_name" {
  type        = string
  default     = "staging"
  description = "Name for the deployment slot."
}

variable "auto_swap_slot_name" {
  type        = string
  default     = null
  description = "Target slot name for auto-swap upon successful deployment to the slot (e.g., 'production'). Defaults to null (manual/pipeline swap)."
}

variable "sticky_app_setting_names" {
  type        = list(string)
  default     = []
  description = "List of application setting names that stick to the slot during swaps and do not rotate."
}

variable "staging_extra_app_settings" {
  type        = map(string)
  default     = {}
  description = "Additional or overriding environment variables applied exclusively to the staging deployment slot."
}

###############################################################################
# Observability & Monitoring
###############################################################################

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Enable Application Insights and diagnostic logging to Azure Log Analytics."
}

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Existing Log Analytics Workspace ID. If null and enable_telemetry is true, a dedicated workspace is created."
}

variable "log_analytics_retention_days" {
  type        = number
  default     = 30
  description = "Data retention duration in days for the managed Log Analytics workspace."
}

variable "application_insights_connection_string" {
  type        = string
  default     = null
  sensitive   = true
  description = "Existing Application Insights connection string. If null and enable_telemetry is true, a dedicated Application Insights instance is created."
}

variable "enable_alerts" {
  type        = bool
  default     = true
  description = "Provision out-of-the-box Azure Monitor metric alerts for 5xx errors, latency, health checks, and capacity saturation."
}

variable "action_group_ids" {
  type        = list(string)
  default     = []
  description = "List of Azure Monitor Action Group resource IDs notified when metric alerts trigger."
}

variable "alert_thresholds" {
  type = object({
    http_5xx_count        = optional(number, 20)
    response_time_seconds = optional(number, 2.0)
    cpu_percentage        = optional(number, 85)
    memory_percentage     = optional(number, 85)
  })
  default = {
    http_5xx_count        = 20
    response_time_seconds = 2.0
    cpu_percentage        = 85
    memory_percentage     = 85
  }
  description = "Metric thresholds triggering SRE alerts over 5-minute evaluation windows."
}

###############################################################################
# Networking, Security & App Settings
###############################################################################

variable "identity_type" {
  type        = string
  default     = "SystemAssigned"
  description = "Managed Service Identity type: 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'."
}

variable "identity_ids" {
  type        = list(string)
  default     = []
  description = "List of User Assigned Managed Identity resource IDs when identity_type includes 'UserAssigned'."
}

variable "virtual_network_subnet_id" {
  type        = string
  default     = null
  description = "Subnet ID for regional Virtual Network integration, allowing containers private network access."
}

variable "ip_restrictions" {
  type = list(object({
    name                      = optional(string)
    ip_address                = optional(string)
    service_tag               = optional(string)
    virtual_network_subnet_id = optional(string)
    priority                  = optional(number, 100)
    action                    = optional(string, "Allow")
    description               = optional(string)
  }))
  default     = []
  description = "Inbound IP/network access restrictions applied to the HTTP API."
}

variable "scm_ip_restrictions" {
  type = list(object({
    name                      = optional(string)
    ip_address                = optional(string)
    service_tag               = optional(string)
    virtual_network_subnet_id = optional(string)
    priority                  = optional(number, 100)
    action                    = optional(string, "Allow")
    description               = optional(string)
  }))
  default     = []
  description = "Inbound IP/network access restrictions applied to SCM management endpoints."
}

variable "extra_app_settings" {
  type        = map(string)
  default     = {}
  description = "Custom application environment variables supplied to the container."
}
