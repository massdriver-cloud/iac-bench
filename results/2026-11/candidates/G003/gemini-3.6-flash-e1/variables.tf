variable "service_name" {
  description = "Name of the web service/application"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging, dev)"
  type        = string
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
}

variable "resource_group_name" {
  description = "Name of existing resource group or new resource group if create_resource_group is true. Default generates a name."
  type        = string
  default     = null
}

variable "create_resource_group" {
  description = "Whether to create the resource group"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to created resources"
  type        = map(string)
  default     = {}
}

# Capacity & Availability
variable "sku_name" {
  description = "App Service Plan SKU (e.g. P1v3, P1v2, B1, S1)"
  type        = string
  default     = "P1v3"
}

variable "min_instances" {
  description = "Minimum number of App Service Plan instances"
  type        = number
  default     = 2
}

variable "max_instances" {
  description = "Maximum number of App Service Plan instances for autoscaling"
  type        = number
  default     = 10
}

variable "zone_balancing_enabled" {
  description = "Enable zone redundancy for the App Service Plan (requires supported region and SKU)"
  type        = bool
  default     = false
}

variable "cpu_scale_out_threshold" {
  description = "CPU percentage threshold to scale out"
  type        = number
  default     = 75
}

variable "cpu_scale_in_threshold" {
  description = "CPU percentage threshold to scale in"
  type        = number
  default     = 25
}

variable "memory_scale_out_threshold" {
  description = "Memory percentage threshold to scale out"
  type        = number
  default     = 80
}

variable "memory_scale_in_threshold" {
  description = "Memory percentage threshold to scale in"
  type        = number
  default     = 30
}

# Container Configuration
variable "docker_image_name" {
  description = "Container image name and tag (e.g. nginx:latest or repository/image:tag)"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
}

variable "docker_registry_url" {
  description = "Docker registry URL (e.g. https://index.docker.io/v1 or ACR login server)"
  type        = string
  default     = null
}

variable "docker_registry_username" {
  description = "Username for Docker registry authentication"
  type        = string
  default     = null
}

variable "docker_registry_password" {
  description = "Password for Docker registry authentication"
  type        = string
  default     = null
  sensitive   = true
}

variable "container_port" {
  description = "Port the container listens on (WEBSITES_PORT)"
  type        = number
  default     = 8080
}

# Health & Rollouts
variable "health_check_path" {
  description = "Path for App Service health check probe (e.g. /health)"
  type        = string
  default     = "/health"
}

variable "health_check_eviction_time_in_minutes" {
  description = "Amount of time in minutes an unhealthy instance can remain in the load balancer before being evicted"
  type        = number
  default     = 10
}

variable "enable_staging_slot" {
  description = "Whether to provision a staging deployment slot for zero-downtime rollouts"
  type        = bool
  default     = true
}

variable "sticky_app_setting_names" {
  description = "List of app setting names that stick to the slot during deployment swaps"
  type        = list(string)
  default     = []
}

# Observability
variable "enable_app_insights" {
  description = "Whether to provision Application Insights and telemetry integration"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics Workspace resource ID. If null and enable_app_insights is true, one will be created."
  type        = string
  default     = null
}

variable "log_retention_in_days" {
  description = "Data retention in days for created Log Analytics workspace"
  type        = number
  default     = 30
}

# Application Configuration
variable "app_settings" {
  description = "Additional key-value pairs for environment variables / app settings"
  type        = map(string)
  default     = {}
}
