variable "service_name" {
  type        = string
  description = "The name of the service/application"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g. dev, staging, prod)"
}

variable "location" {
  type        = string
  description = "The Azure region where resources will be created"
}

variable "create_resource_group" {
  type        = bool
  default     = true
  description = "Whether to create a new resource group or use an existing one"
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "The name of the resource group (required if create_resource_group is false)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to all resources"
}

# Capacity & Service Plan Variables
variable "service_plan_id" {
  type        = string
  default     = null
  description = "ID of an existing App Service Plan to use"
}

variable "sku_name" {
  type        = string
  default     = "P1v3"
  description = "SKU for the App Service Plan"
}

variable "worker_count" {
  type        = number
  default     = 2
  description = "Number of workers for the App Service Plan"
}

variable "zone_balancing_enabled" {
  type        = bool
  default     = false
  description = "Whether to enable zone redundancy for the App Service Plan"
}

# Autoscaling Variables
variable "enable_autoscaling" {
  type        = bool
  default     = true
  description = "Whether to enable autoscaling on the App Service Plan"
}

variable "autoscale_min_capacity" {
  type        = number
  default     = 2
  description = "Minimum instance count for autoscaling"
}

variable "autoscale_max_capacity" {
  type        = number
  default     = 10
  description = "Maximum instance count for autoscaling"
}

variable "autoscale_default_capacity" {
  type        = number
  default     = 2
  description = "Default instance count for autoscaling"
}

variable "autoscale_cpu_scale_out_threshold" {
  type        = number
  default     = 75
  description = "CPU percentage threshold to trigger scale out"
}

variable "autoscale_cpu_scale_in_threshold" {
  type        = number
  default     = 25
  description = "CPU percentage threshold to trigger scale in"
}

# Container & App Configuration Variables
variable "container_image" {
  type        = string
  default     = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
  description = "Container image name and tag"
}

variable "docker_registry_url" {
  type        = string
  default     = null
  description = "Docker registry URL"
}

variable "docker_registry_username" {
  type        = string
  default     = null
  description = "Docker registry username"
}

variable "docker_registry_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Docker registry password"
}

variable "container_port" {
  type        = number
  default     = 80
  description = "Port exposed by the container"
}

variable "app_settings" {
  type        = map(string)
  default     = {}
  description = "Application settings (environment variables)"
}

variable "connection_strings" {
  type = list(object({
    name  = string
    type  = string
    value = string
  }))
  default     = []
  description = "List of connection strings to configure"
}

# Health & Rollouts
variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path for HTTP health check probe"
}

variable "health_check_eviction_time_in_minutes" {
  type        = number
  default     = 5
  description = "Time in minutes before an unhealthy instance is evicted"
}

variable "enable_staging_slot" {
  type        = bool
  default     = true
  description = "Whether to create a staging deployment slot for zero-downtime rollouts"
}

# Networking & Security
variable "virtual_network_subnet_id" {
  type        = string
  default     = null
  description = "Subnet ID for VNet integration"
}

variable "ip_restrictions" {
  type = list(object({
    name                      = string
    ip_address                = optional(string)
    service_tag               = optional(string)
    virtual_network_subnet_id = optional(string)
    action                    = optional(string, "Allow")
    priority                  = optional(number, 100)
    description               = optional(string)
  }))
  default     = []
  description = "List of IP restrictions / access restrictions for the app"
}

# Observability Variables
variable "enable_application_insights" {
  type        = bool
  default     = true
  description = "Whether to enable Application Insights integration"
}

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "ID of an existing Log Analytics Workspace"
}

variable "application_insights_connection_string" {
  type        = string
  default     = null
  description = "Connection string of an existing Application Insights instance"
}

variable "application_insights_instrumentation_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "Instrumentation key of an existing Application Insights instance"
}

variable "enable_diagnostic_settings" {
  type        = bool
  default     = true
  description = "Whether to enable diagnostic settings sending logs and metrics to Log Analytics"
}

variable "enable_alerts" {
  type        = bool
  default     = true
  description = "Whether to enable SRE metric alerts for HTTP 5xx errors, high CPU, and high memory"
}

variable "alert_action_group_ids" {
  type        = list(string)
  default     = []
  description = "Action group IDs to notify when alerts fire"
}

variable "alert_5xx_threshold" {
  type        = number
  default     = 10
  description = "Threshold for HTTP 5xx error count alert over 5 minutes"
}

variable "alert_cpu_threshold" {
  type        = number
  default     = 85
  description = "Threshold for CPU percentage alert over 5 minutes"
}

variable "alert_memory_threshold" {
  type        = number
  default     = 85
  description = "Threshold for Memory percentage alert over 5 minutes"
}
