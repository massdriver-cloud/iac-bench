# ---------------------------------------------------------------------------------------------------------------------
# Service Identity & Placement Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "service_name" {
  description = "The name of the containerized HTTP service (e.g., 'order-api', 'payment-gateway')."
  type        = string
}

variable "environment" {
  description = "Deployment environment name (e.g., 'production', 'staging', 'dev')."
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be provisioned (e.g., 'eastus', 'westeurope')."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the Azure Resource Group."
  type        = string
}

variable "create_resource_group" {
  description = "Whether to create the resource group. If false, an existing resource group with `resource_group_name` will be used."
  type        = bool
  default     = true
}

variable "custom_app_name" {
  description = "Optional custom name override for the Azure Linux Web App. Defaults to a standard unique naming convention."
  type        = string
  default     = null
}

variable "custom_plan_name" {
  description = "Optional custom name override for the Azure App Service Plan. Defaults to a standard unique naming convention."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources. Merged with standard SRE tags."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------------------------------------------------
# Capacity & Sizing Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "sku_name" {
  description = "The SKU tier for the App Service Plan (e.g., 'P1v3', 'P2v3', 'B1'). Defaults to P1v3 for production container workloads."
  type        = string
  default     = "P1v3"
}

variable "service_plan_id" {
  description = "Existing App Service Plan ID to host this service. If null, a dedicated App Service Plan is created."
  type        = string
  default     = null
}

variable "min_capacity" {
  description = "Minimum instance count for autoscaling and baseline capacity. Defaults to 2 for high availability."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum instance count for autoscaling during peak loads."
  type        = number
  default     = 10
}

variable "default_capacity" {
  description = "Default/starting instance count for the App Service Plan."
  type        = number
  default     = 2
}

variable "autoscale_enabled" {
  description = "Enable metric-based horizontal autoscaling for the App Service Plan."
  type        = bool
  default     = true
}

variable "autoscale_cpu_scale_out_threshold" {
  description = "CPU percentage threshold to trigger scale-out."
  type        = number
  default     = 75
}

variable "autoscale_cpu_scale_in_threshold" {
  description = "CPU percentage threshold to trigger scale-in."
  type        = number
  default     = 25
}

variable "autoscale_memory_scale_out_threshold" {
  description = "Memory percentage threshold to trigger scale-out."
  type        = number
  default     = 80
}

variable "autoscale_memory_scale_in_threshold" {
  description = "Memory percentage threshold to trigger scale-in."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------------------------------------------------
# Availability & Resilience Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "zone_redundancy_enabled" {
  description = "Enable Availability Zone balancing across fault domains. Enforces minimum 3 workers."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------------------------------------------------
# Health & Auto-Healing Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "health_check_path" {
  description = "The HTTP health check probe path monitored by the App Service load balancer (e.g., '/healthz')."
  type        = string
  default     = "/healthz"
}

variable "health_check_eviction_time_in_min" {
  description = "The amount of time in minutes (2-10) an unhealthy instance can fail health checks before platform eviction."
  type        = number
  default     = 5
}

variable "auto_heal_enabled" {
  description = "Enable App Service auto-healing rules to recycle unhealthy container instances automatically."
  type        = bool
  default     = true
}

variable "auto_heal_5xx_count" {
  description = "Number of HTTP 5xx responses within the time interval that triggers an auto-heal container recycle."
  type        = number
  default     = 20
}

variable "auto_heal_time_interval" {
  description = "Time window for auto-heal rule evaluation (formatted as hh:mm:ss)."
  type        = string
  default     = "00:05:00"
}

# ---------------------------------------------------------------------------------------------------------------------
# Rollouts & Deployment Slots Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_staging_slot" {
  description = "Deploy a staging deployment slot for zero-downtime rollouts and pre-warming."
  type        = bool
  default     = true
}

variable "sticky_app_settings" {
  description = "List of app setting keys that remain pinned to their slot during deployment slot swaps."
  type        = list(string)
  default     = ["SLOT_NAME", "APP_ENV", "ENVIRONMENT"]
}

variable "staging_custom_app_settings" {
  description = "Environment variables specific to the staging deployment slot."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------------------------------------------------
# Container & Application Configuration Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "container_image" {
  description = "The container image to run (e.g., 'mcr.microsoft.com/azure-app-service/samples/aspnetcore-helloworld:latest')."
  type        = string
  default     = "mcr.microsoft.com/azure-app-service/samples/aspnetcore-helloworld:latest"
}

variable "container_port" {
  description = "The HTTP port the containerized application listens on. App Service forwards incoming traffic to this port."
  type        = number
  default     = 8080
}

variable "docker_registry_url" {
  description = "Container registry URL (e.g. 'https://myregistry.azurecr.io'). Defaults to null for public registries."
  type        = string
  default     = null
}

variable "docker_registry_username" {
  description = "Container registry username, if authentication is required."
  type        = string
  default     = null
}

variable "docker_registry_password" {
  description = "Container registry password, if authentication is required."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_registry_use_managed_identity" {
  description = "Configure App Service to pull container images using the Web App's Managed Identity."
  type        = bool
  default     = false
}

variable "custom_app_settings" {
  description = "Key-value map of custom environment variables / app settings passed to the container."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------------------------------------------------
# Networking & Security Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "virtual_network_subnet_id" {
  description = "Subnet ID for regional Virtual Network integration. Directs outbound container traffic through the VNet."
  type        = string
  default     = null
}

variable "allowed_ip_cidrs" {
  description = "List of allowed client IP CIDR ranges. If empty, public traffic is permitted."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------------------------------------------------
# Observability & Alerting Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "Resource ID of an existing Log Analytics Workspace. If null, a dedicated workspace is created."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Data retention period in days for the managed Log Analytics Workspace."
  type        = number
  default     = 30
}

variable "application_insights_connection_string" {
  description = "Connection string of an existing Application Insights resource. If null, a dedicated instance is created."
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_alerts" {
  description = "Create standard SRE metric alerts for latency, error rate, CPU, and memory."
  type        = bool
  default     = true
}

variable "alert_action_group_ids" {
  description = "List of Azure Monitor Action Group resource IDs to notify when alerts fire."
  type        = list(string)
  default     = []
}

variable "alert_5xx_threshold" {
  description = "Threshold for total HTTP 5xx responses in a 5-minute window to trigger an alert."
  type        = number
  default     = 10
}

variable "alert_cpu_threshold" {
  description = "Threshold for average CPU percentage in a 5-minute window to trigger an alert."
  type        = number
  default     = 85
}

variable "alert_memory_threshold" {
  description = "Threshold for average memory percentage in a 5-minute window to trigger an alert."
  type        = number
  default     = 85
}

variable "alert_response_time_threshold" {
  description = "Threshold for average response time in seconds in a 5-minute window to trigger an alert."
  type        = number
  default     = 2.0
}
