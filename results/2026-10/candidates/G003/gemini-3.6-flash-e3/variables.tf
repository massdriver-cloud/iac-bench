# --- Basic & Resource Group Variables ---
variable "name" {
  type        = string
  description = "Name of the web application service. Used as a base for resource names."
}

variable "location" {
  type        = string
  description = "Azure region where resources will be deployed."
}

variable "create_resource_group" {
  type        = bool
  default     = true
  description = "Whether to create a new resource group. If false, resource_group_name must refer to an existing resource group."
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Name of the resource group. Required if create_resource_group is false; optional if true (defaults to 'rg-name')."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Resource tags to apply to all deployed resources."
}

# --- Service Plan & Capacity Variables ---
variable "create_service_plan" {
  type        = bool
  default     = true
  description = "Whether to create a new App Service Plan. If false, service_plan_id must be supplied."
}

variable "service_plan_id" {
  type        = string
  default     = null
  description = "ID of an existing App Service Plan. Required if create_service_plan is false."
}

variable "service_plan_name" {
  type        = string
  default     = null
  description = "Custom name for the App Service Plan. Defaults to 'asp-name' if created."
}

variable "sku_name" {
  type        = string
  default     = "P1v3"
  description = "SKU size for the App Service Plan (e.g. B1, P1v2, P1v3, P2v3, S1)."
}

variable "worker_count" {
  type        = number
  default     = 1
  description = "Initial number of workers allocated to the App Service Plan."
}

variable "zone_balancing_enabled" {
  type        = bool
  default     = false
  description = "Should the Service Plan be zone balanced across availability zones."
}

# --- Autoscaling Variables ---
variable "enable_autoscaling" {
  type        = bool
  default     = true
  description = "Enable automatic scaling for the App Service Plan."
}

variable "autoscale_min_capacity" {
  type        = number
  default     = 1
  description = "Minimum worker instance count for autoscaling."
}

variable "autoscale_max_capacity" {
  type        = number
  default     = 5
  description = "Maximum worker instance count for autoscaling."
}

variable "autoscale_default_capacity" {
  type        = number
  default     = 2
  description = "Default worker instance count for autoscaling."
}

variable "cpu_scale_out_threshold" {
  type        = number
  default     = 70
  description = "CPU percentage threshold above which instances will scale out."
}

variable "cpu_scale_in_threshold" {
  type        = number
  default     = 25
  description = "CPU percentage threshold below which instances will scale in."
}

variable "memory_scale_out_threshold" {
  type        = number
  default     = 80
  description = "Memory percentage threshold above which instances will scale out."
}

variable "memory_scale_in_threshold" {
  type        = number
  default     = 30
  description = "Memory percentage threshold below which instances will scale in."
}

# --- App Service & Container Configuration ---
variable "container_image_name" {
  type        = string
  description = "Container image name and tag (e.g., 'nginx:latest' or 'myregistry.azurecr.io/myapp:v1.0.0')."
}

variable "container_registry_url" {
  type        = string
  default     = "https://index.docker.io/v1"
  description = "Container registry server URL."
}

variable "container_registry_username" {
  type        = string
  default     = null
  description = "Username for container registry authentication."
}

variable "container_registry_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Password for container registry authentication."
}

variable "container_registry_use_managed_identity" {
  type        = bool
  default     = false
  description = "Use Managed Identity to pull images from container registry (e.g. Azure Container Registry)."
}

variable "container_registry_managed_identity_client_id" {
  type        = string
  default     = null
  description = "Client ID of User-Assigned Managed Identity for container registry access."
}

variable "always_on" {
  type        = bool
  default     = true
  description = "Keep the App Service loaded even when there is no traffic."
}

variable "http2_enabled" {
  type        = bool
  default     = true
  description = "Enable HTTP/2 protocol support."
}

variable "https_only" {
  type        = bool
  default     = true
  description = "Force HTTPS redirect on all incoming web requests."
}

variable "min_tls_version" {
  type        = string
  default     = "1.2"
  description = "Minimum TLS version required for clients."
}

variable "ftps_state" {
  type        = string
  default     = "Disabled"
  description = "FTPS enforcement state (AllAllowed, FtpsOnly, Disabled)."
}

variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "HTTP endpoint path used for health check probes."
}

variable "health_check_eviction_time_in_minutes" {
  type        = number
  default     = 5
  description = "Time in minutes before an unhealthy instance is removed from load balancer rotation."
}

variable "identity_type" {
  type        = string
  default     = "SystemAssigned"
  description = "Managed Identity type (SystemAssigned, UserAssigned, SystemAssigned, UserAssigned)."
}

variable "identity_ids" {
  type        = list(string)
  default     = []
  description = "List of User Assigned Identity IDs if UserAssigned identity is specified."
}

variable "app_settings" {
  type        = map(string)
  default     = {}
  description = "Key-value map of application settings (environment variables)."
}

variable "sticky_app_setting_names" {
  type        = list(string)
  default     = []
  description = "List of app setting names that should remain sticky to the slot during deployment swaps."
}

variable "connection_strings" {
  type = list(object({
    name  = string
    type  = string
    value = string
  }))
  default     = []
  description = "List of connection string configurations."
}

# --- Deployment Slot Variables ---
variable "enable_staging_slot" {
  type        = bool
  default     = true
  description = "Enable creation of a staging deployment slot for zero-downtime rollouts."
}

variable "staging_slot_name" {
  type        = string
  default     = "staging"
  description = "Name for the deployment slot."
}

variable "staging_container_image_name" {
  type        = string
  default     = null
  description = "Container image name for the staging slot. Defaults to container_image_name if null."
}

variable "staging_app_settings" {
  type        = map(string)
  default     = {}
  description = "App settings specific to the staging deployment slot."
}

# --- Networking Variables ---
variable "vnet_subnet_id" {
  type        = string
  default     = null
  description = "Subnet ID for regional VNet integration."
}

variable "vnet_route_all_enabled" {
  type        = bool
  default     = true
  description = "Should all outbound traffic be routed through the integrated VNet."
}

variable "ip_restrictions" {
  type        = list(any)
  default     = []
  description = "List of IP access restriction rules for the Web App."
}

# --- Observability & Application Insights Variables ---
variable "create_application_insights" {
  type        = bool
  default     = true
  description = "Whether to create a new Application Insights instance."
}

variable "application_insights_name" {
  type        = string
  default     = null
  description = "Custom name for Application Insights. Defaults to 'appi-name'."
}

variable "application_insights_instrumentation_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "Instrumentation key of existing Application Insights instance (if not creating new)."
}

variable "application_insights_connection_string" {
  type        = string
  default     = null
  sensitive   = true
  description = "Connection string of existing Application Insights instance (if not creating new)."
}

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Log Analytics Workspace ID for Application Insights and Diagnostic Settings."
}

variable "enable_diagnostic_settings" {
  type        = bool
  default     = true
  description = "Enable sending diagnostic logs and metrics to Log Analytics workspace."
}

# --- Alerting Variables ---
variable "enable_alerts" {
  type        = bool
  default     = true
  description = "Enable standard SRE metric alerts."
}

variable "action_group_ids" {
  type        = list(string)
  default     = []
  description = "List of Action Group IDs to trigger when metric alerts fire."
}

variable "alert_http_5xx_threshold" {
  type        = number
  default     = 10
  description = "Threshold count for HTTP 5xx errors to trigger an alert over 5 minutes."
}

variable "alert_response_time_threshold" {
  type        = number
  default     = 2.0
  description = "Average HTTP response time threshold (in seconds) to trigger an alert over 5 minutes."
}

variable "alert_cpu_threshold" {
  type        = number
  default     = 85
  description = "CPU percentage threshold to trigger an alert over 5 minutes."
}

variable "alert_memory_threshold" {
  type        = number
  default     = 85
  description = "Memory percentage threshold to trigger an alert over 5 minutes."
}
