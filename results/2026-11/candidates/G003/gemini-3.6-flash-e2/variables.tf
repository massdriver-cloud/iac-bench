# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "name" {
  description = "Name of the App Service and associated resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
}

variable "location" {
  description = "Azure region where resources will be deployed."
  type        = string
}

# -----------------------------------------------------------------------------
# Resource Group & Capacity (App Service Plan)
# -----------------------------------------------------------------------------

variable "create_resource_group" {
  description = "Whether to create the Resource Group."
  type        = bool
  default     = false
}

variable "create_service_plan" {
  description = "Whether to create a new App Service Plan."
  type        = bool
  default     = true
}

variable "service_plan_id" {
  description = "Existing App Service Plan ID if create_service_plan is false."
  type        = string
  default     = null
}

variable "sku_name" {
  description = "App Service Plan SKU (e.g., B1, S1, P1v2, P1v3)."
  type        = string
  default     = "P1v3"
}

variable "worker_count" {
  description = "Number of workers (instances) for the App Service Plan."
  type        = number
  default     = 2
}

variable "zone_balancing_enabled" {
  description = "Enable zone balancing for high availability across availability zones."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Container & Application Configuration
# -----------------------------------------------------------------------------

variable "docker_image_name" {
  description = "Container image name and tag (e.g., 'nginx:latest' or 'myregistry.azurecr.io/myapp:v1.0.0')."
  type        = string
  default     = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
}

variable "docker_registry_url" {
  description = "Container registry URL (e.g., 'https://index.docker.io/v1' or 'https://myregistry.azurecr.io')."
  type        = string
  default     = null
}

variable "docker_registry_username" {
  description = "Container registry username."
  type        = string
  default     = null
  sensitive   = true
}

variable "docker_registry_password" {
  description = "Container registry password."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_registry_use_managed_identity" {
  description = "Use managed identity to authenticate with Azure Container Registry."
  type        = bool
  default     = false
}

variable "app_settings" {
  description = "Map of environment variables / app settings for the App Service."
  type        = map(string)
  default     = {}
}

variable "vnet_subnet_id" {
  description = "Subnet ID for regional VNet integration."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Availability & Health
# -----------------------------------------------------------------------------

variable "always_on" {
  description = "Keep the App Service loaded even when idle."
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Health check path for App Service instance health monitoring (e.g. '/health')."
  type        = string
  default     = "/health"
}

variable "health_check_eviction_time_in_minutes" {
  description = "Eviction time in minutes for unhealthy instances (between 2 and 10)."
  type        = number
  default     = 10
}

variable "https_only" {
  description = "Force HTTPS for all inbound web traffic."
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version required."
  type        = string
  default     = "1.2"
}

variable "http2_enabled" {
  description = "Enable HTTP/2 protocol support."
  type        = bool
  default     = true
}

variable "client_affinity_enabled" {
  description = "Enable ARR session affinity."
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for Cross-Origin Resource Sharing (CORS)."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Managed Identity
# -----------------------------------------------------------------------------

variable "identity_type" {
  description = "Managed Identity type ('SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned')."
  type        = string
  default     = "SystemAssigned"
}

variable "identity_ids" {
  description = "List of User Assigned Identity IDs when identity_type contains 'UserAssigned'."
  type        = list(string)
  default     = null
}

# -----------------------------------------------------------------------------
# Observability & Monitoring
# -----------------------------------------------------------------------------

variable "enable_application_insights" {
  description = "Create and integrate Azure Application Insights."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for Application Insights and Diagnostic Settings."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Rollout & Deployment Slots
# -----------------------------------------------------------------------------

variable "enable_staging_slot" {
  description = "Create a staging deployment slot for zero-downtime rollouts."
  type        = bool
  default     = false
}

variable "staging_slot_name" {
  description = "Name of the staging deployment slot."
  type        = string
  default     = "staging"
}

# -----------------------------------------------------------------------------
# Autoscale Settings
# -----------------------------------------------------------------------------

variable "enable_autoscale" {
  description = "Enable autoscale rules for the App Service Plan based on CPU utilization."
  type        = bool
  default     = false
}

variable "autoscale_min_capacity" {
  description = "Minimum capacity (instance count) for autoscale."
  type        = number
  default     = 2
}

variable "autoscale_max_capacity" {
  description = "Maximum capacity (instance count) for autoscale."
  type        = number
  default     = 5
}

variable "autoscale_default_capacity" {
  description = "Default capacity (instance count) for autoscale."
  type        = number
  default     = 2
}

variable "autoscale_cpu_scale_out_threshold" {
  description = "CPU percentage threshold to scale out (increase instance count)."
  type        = number
  default     = 75
}

variable "autoscale_cpu_scale_in_threshold" {
  description = "CPU percentage threshold to scale in (decrease instance count)."
  type        = number
  default     = 25
}

# -----------------------------------------------------------------------------
# Resource Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Map of tags to apply to all created Azure resources."
  type        = map(string)
  default     = {}
}
