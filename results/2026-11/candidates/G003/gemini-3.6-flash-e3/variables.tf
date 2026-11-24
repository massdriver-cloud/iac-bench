# ==============================================================================
# General & Naming
# ==============================================================================

variable "name" {
  type        = string
  description = "Name of the service/application. Used as the base name for deployed resources."
}

variable "location" {
  type        = string
  description = "Azure region where resources will be created."
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Name of an existing Azure Resource Group. If set to null, a new resource group 'rg-<name>' will be created."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A mapping of tags to assign to all resources."
  default     = {}
}

# ==============================================================================
# Container & App Configuration
# ==============================================================================

variable "container_image" {
  type        = string
  description = "Docker image name and tag (e.g., 'mcr.microsoft.com/azuredocs/aci-helloworld:latest')."
  default     = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
}

variable "container_registry_url" {
  type        = string
  description = "Container registry URL (e.g., 'https://index.docker.io/v1' or ACR URL 'https://myregistry.azurecr.io')."
  default     = null
}

variable "container_registry_username" {
  type        = string
  description = "Username for authenticating to a private container registry."
  default     = null
}

variable "container_registry_password" {
  type        = string
  description = "Password for authenticating to a private container registry."
  default     = null
  sensitive   = true
}

variable "container_registry_use_managed_identity" {
  type        = bool
  description = "Use managed identity to authenticate with Azure Container Registry (ACR)."
  default     = false
}

variable "container_port" {
  type        = number
  description = "Port exposed by the container HTTP API (sets WEBSITES_PORT)."
  default     = 80
}

variable "app_command_line" {
  type        = string
  description = "App command line argument for container execution."
  default     = null
}

variable "app_settings" {
  type        = map(string)
  description = "Map of application settings / environment variables."
  default     = {}
}

variable "connection_strings" {
  type = list(object({
    name  = string
    type  = string
    value = string
  }))
  description = "List of connection string configurations (type can be SQLAzure, SQLServer, PostgreSQL, MySQL, Custom, etc.)."
  default     = []
}

# ==============================================================================
# Capacity & Scaling
# ==============================================================================

variable "custom_service_plan_id" {
  type        = string
  description = "ID of an existing App Service Plan. If null, a new App Service Plan 'asp-<name>' will be created."
  default     = null
}

variable "sku_name" {
  type        = string
  description = "SKU for the App Service Plan (e.g. 'P1v2', 'P1v3', 'B1', 'S1'). Production recommended: 'P1v2' or 'P1v3'."
  default     = "P1v2"
}

variable "worker_count" {
  type        = number
  description = "Initial number of workers/instances for the App Service Plan."
  default     = 2
}

variable "zone_balancing_enabled" {
  type        = bool
  description = "Enable zone balancing for high availability across availability zones."
  default     = false
}

variable "enable_autoscaling" {
  type        = bool
  description = "Enable autoscale settings on the App Service Plan based on CPU and Memory usage."
  default     = true
}

variable "autoscale_min_capacity" {
  type        = number
  description = "Minimum instance count for autoscaling."
  default     = 2
}

variable "autoscale_max_capacity" {
  type        = number
  description = "Maximum instance count for autoscaling."
  default     = 5
}

variable "autoscale_cpu_scale_out_threshold" {
  type        = number
  description = "CPU percentage threshold to trigger scale-out."
  default     = 80
}

variable "autoscale_cpu_scale_in_threshold" {
  type        = number
  description = "CPU percentage threshold to trigger scale-in."
  default     = 20
}

variable "autoscale_memory_scale_out_threshold" {
  type        = number
  description = "Memory percentage threshold to trigger scale-out."
  default     = 80
}

variable "autoscale_memory_scale_in_threshold" {
  type        = number
  description = "Memory percentage threshold to trigger scale-in."
  default     = 20
}

# ==============================================================================
# Availability & Health
# ==============================================================================

variable "always_on" {
  type        = bool
  description = "Keep the App Service loaded even when there is no traffic."
  default     = true
}

variable "health_check_path" {
  type        = string
  description = "HTTP path for health check probe (e.g. '/health' or '/healthz')."
  default     = "/health"
}

variable "health_check_eviction_time_in_minutes" {
  type        = number
  description = "Amount of time in minutes an unhealthy instance can remain before eviction (2-10 mins)."
  default     = 10
}

variable "http2_enabled" {
  type        = bool
  description = "Enable HTTP/2 protocol."
  default     = true
}

# ==============================================================================
# Rollouts & Staging Slot
# ==============================================================================

variable "enable_staging_slot" {
  type        = bool
  description = "Create a staging deployment slot for zero-downtime blue/green rollouts."
  default     = true
}

variable "staging_container_image" {
  type        = string
  description = "Container image for staging slot. If null, defaults to var.container_image."
  default     = null
}

variable "staging_app_settings" {
  type        = map(string)
  description = "Additional app settings specific to the staging slot."
  default     = {}
}

# ==============================================================================
# Observability & Telemetry
# ==============================================================================

variable "enable_observability" {
  type        = bool
  description = "Enable Log Analytics Workspace, Application Insights, and Diagnostic Settings."
  default     = true
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Existing Log Analytics Workspace ID. If null and enable_observability is true, a new workspace will be created."
  default     = null
}

variable "log_analytics_retention_days" {
  type        = number
  description = "Data retention period in days for the created Log Analytics Workspace."
  default     = 30
}

variable "application_insights_id" {
  type        = string
  description = "Existing Application Insights ID. If null and enable_observability is true, new Application Insights will be created."
  default     = null
}

# ==============================================================================
# Networking & Security
# ==============================================================================

variable "https_only" {
  type        = bool
  description = "Redirect all HTTP traffic to HTTPS."
  default     = true
}

variable "minimum_tls_version" {
  type        = string
  description = "Minimum TLS version required for HTTPS requests."
  default     = "1.2"
}

variable "ftps_state" {
  type        = string
  description = "FTPS state ('Disabled', 'AllAllowed', 'FtpsOnly')."
  default     = "Disabled"
}

variable "vnet_subnet_id" {
  type        = string
  description = "Subnet ID for regional Virtual Network integration."
  default     = null
}

variable "vnet_route_all_enabled" {
  type        = bool
  description = "Route all outbound traffic through the integrated Virtual Network."
  default     = true
}

variable "identity_type" {
  type        = string
  description = "Type of Managed Identity ('SystemAssigned', 'UserAssigned', 'SystemAssigned, UserAssigned')."
  default     = "SystemAssigned"
}

variable "identity_ids" {
  type        = list(string)
  description = "List of User Assigned Identity IDs if identity_type includes UserAssigned."
  default     = []
}

variable "ip_restrictions" {
  type = list(object({
    name                      = string
    ip_address                = optional(string)
    service_tag               = optional(string)
    virtual_network_subnet_id = optional(string)
    action                    = optional(string)
    priority                  = optional(number)
  }))
  description = "List of IP restriction rules for inbound app access."
  default     = []
}

variable "scm_ip_restrictions" {
  type = list(object({
    name                      = string
    ip_address                = optional(string)
    service_tag               = optional(string)
    virtual_network_subnet_id = optional(string)
    action                    = optional(string)
    priority                  = optional(number)
  }))
  description = "List of IP restriction rules for inbound SCM access."
  default     = []
}
