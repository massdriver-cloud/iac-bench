variable "name" {
  description = "Name of the web application and base name for resources."
  type        = string
}

variable "location" {
  description = "Azure region for resource deployment."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
}

variable "create_resource_group" {
  description = "Whether to create a new Resource Group or use an existing one."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)."
  type        = string
  default     = "prod"
}

variable "container_image" {
  description = "Container image name and tag (e.g. 'mcr.microsoft.com/azuredocs/aci-helloworld:latest' or 'nginx:latest')."
  type        = string
}

variable "container_registry_url" {
  description = "URL of the container registry (e.g. 'https://index.docker.io' or 'https://myregistry.azurecr.io')."
  type        = string
  default     = "https://index.docker.io"
}

variable "container_registry_username" {
  description = "Username for container registry authentication."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_registry_password" {
  description = "Password for container registry authentication."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_registry_use_managed_identity" {
  description = "Whether to use managed identity for container registry authentication."
  type        = bool
  default     = false
}

variable "container_port" {
  description = "Port exposed by the container for HTTP traffic."
  type        = number
  default     = 80
}

variable "sku_name" {
  description = "SKU for the App Service Plan (e.g. P1v3, B1, S1)."
  type        = string
  default     = "P1v3"
}

variable "worker_count" {
  description = "Number of workers allocated to the App Service Plan."
  type        = number
  default     = 2
}

variable "zone_balancing_enabled" {
  description = "Should the App Service Plan be zone redundant."
  type        = bool
  default     = false
}

variable "always_on" {
  description = "Should the app be kept loaded even when there is no traffic."
  type        = bool
  default     = true
}

variable "enable_http2" {
  description = "Enable HTTP/2 protocol on the web app."
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Path for App Service health checks (e.g. '/health' or '/healthz')."
  type        = string
  default     = "/health"
}

variable "health_check_eviction_time_in_minutes" {
  description = "Time in minutes before an unhealthy instance is evicted from the load balancer pool."
  type        = number
  default     = 5
}

variable "enable_autoscale" {
  description = "Enable autoscale settings for the App Service Plan."
  type        = bool
  default     = true
}

variable "autoscale_min_capacity" {
  description = "Minimum instance count for autoscale."
  type        = number
  default     = 2
}

variable "autoscale_max_capacity" {
  description = "Maximum instance count for autoscale."
  type        = number
  default     = 10
}

variable "autoscale_default_capacity" {
  description = "Default instance count for autoscale."
  type        = number
  default     = 2
}

variable "autoscale_cpu_scale_out_threshold" {
  description = "CPU percentage threshold to trigger scale out."
  type        = number
  default     = 70
}

variable "autoscale_cpu_scale_in_threshold" {
  description = "CPU percentage threshold to trigger scale in."
  type        = number
  default     = 25
}

variable "autoscale_memory_scale_out_threshold" {
  description = "Memory percentage threshold to trigger scale out."
  type        = number
  default     = 80
}

variable "autoscale_memory_scale_in_threshold" {
  description = "Memory percentage threshold to trigger scale in."
  type        = number
  default     = 30
}

variable "enable_staging_slot" {
  description = "Create a staging slot for safe rollouts and zero-downtime deployments."
  type        = bool
  default     = true
}

variable "staging_slot_name" {
  description = "Name of the staging slot."
  type        = string
  default     = "staging"
}

variable "create_log_analytics_workspace" {
  description = "Whether to create a new Log Analytics Workspace."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics Workspace Resource ID (if create_log_analytics_workspace is false)."
  type        = string
  default     = null
}

variable "log_retention_in_days" {
  description = "Log retention period in days for Log Analytics."
  type        = number
  default     = 30
}

variable "enable_application_insights" {
  description = "Enable Application Insights for observability."
  type        = bool
  default     = true
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings to stream web app logs and metrics to Log Analytics."
  type        = bool
  default     = true
}

variable "vnet_subnet_id" {
  description = "Subnet ID for regional VNet integration."
  type        = string
  default     = null
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS."
  type        = list(string)
  default     = []
}

variable "cors_support_credentials" {
  description = "Allow credentials in CORS requests."
  type        = bool
  default     = false
}

variable "ip_restrictions" {
  description = "List of IP restriction rules for the web app."
  type = list(object({
    name                      = string
    ip_address                = optional(string)
    service_tag               = optional(string)
    virtual_network_subnet_id = optional(string)
    action                    = optional(string, "Allow")
    priority                  = optional(number, 100)
    description               = optional(string)
  }))
  default = []
}

variable "app_settings" {
  description = "Map of application settings (environment variables) for the web app."
  type        = map(string)
  default     = {}
}

variable "slot_app_settings" {
  description = "Map of application settings for the staging slot."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
