# -----------------------------------------------------------------------------
# Core Service & Resource Identification (Required)
# -----------------------------------------------------------------------------

variable "app_name" {
  type        = string
  description = "The name of the web service/application. Used for naming the Azure App Service and associated resources. Must be globally unique across Azure."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the Azure Resource Group where resources will be deployed."
}

variable "location" {
  type        = string
  description = "The Azure region where resources will be deployed."
}

variable "container_image" {
  type        = string
  description = "The container image name and tag to deploy (e.g. 'mcr.microsoft.com/dotnet/samples:aspnetapp' or 'repo/image:tag')."
}

# -----------------------------------------------------------------------------
# Capacity & App Service Plan Configuration
# -----------------------------------------------------------------------------

variable "service_plan_id" {
  type        = string
  default     = null
  description = "Existing App Service Plan ID to host the application. If null, a dedicated App Service Plan will be created."
}

variable "service_plan_name" {
  type        = string
  default     = null
  description = "Name of the App Service Plan to create when service_plan_id is null. Defaults to 'asp-{app_name}'."
}

variable "sku_name" {
  type        = string
  default     = "P1v3"
  description = "The SKU for the App Service Plan (e.g., P1v3, P2v3, S1). Defaults to P1v3 for production container workloads."
}

variable "worker_count" {
  type        = number
  default     = 2
  description = "Base number of worker instances in the App Service Plan. Defaults to 2 for high availability."
}

variable "zone_redundant" {
  type        = bool
  default     = false
  description = "Whether the App Service Plan should be zone-redundant across availability zones (requires Premium v3 or higher in supported regions)."
}

variable "autoscale_enabled" {
  type        = bool
  default     = true
  description = "Whether to enable metric-based horizontal autoscaling on the managed App Service Plan."
}

variable "autoscale_min_capacity" {
  type        = number
  default     = 2
  description = "Minimum number of instances during autoscaling."
}

variable "autoscale_max_capacity" {
  type        = number
  default     = 10
  description = "Maximum number of instances during autoscaling."
}

variable "autoscale_default_capacity" {
  type        = number
  default     = 2
  description = "Default number of instances during autoscaling."
}

variable "autoscale_cpu_scale_out_threshold" {
  type        = number
  default     = 70
  description = "Average CPU percentage over 5 minutes to trigger scale-out (+1 instance)."
}

variable "autoscale_cpu_scale_in_threshold" {
  type        = number
  default     = 25
  description = "Average CPU percentage over 5 minutes to trigger scale-in (-1 instance)."
}

variable "autoscale_memory_scale_out_threshold" {
  type        = number
  default     = 80
  description = "Average memory percentage over 5 minutes to trigger scale-out (+1 instance)."
}

variable "autoscale_memory_scale_in_threshold" {
  type        = number
  default     = 40
  description = "Average memory percentage over 5 minutes to trigger scale-in (-1 instance)."
}

# -----------------------------------------------------------------------------
# Availability & Security Configuration
# -----------------------------------------------------------------------------

variable "always_on" {
  type        = bool
  default     = true
  description = "Keep the container warm and prevent idle unloading."
}

variable "client_affinity_enabled" {
  type        = bool
  default     = false
  description = "Enable ARR affinity cookie routing. Disabled by default for stateless HTTP APIs to ensure even load balancing."
}

variable "https_only" {
  type        = bool
  default     = true
  description = "Redirect all HTTP traffic to HTTPS."
}

variable "http2_enabled" {
  type        = bool
  default     = true
  description = "Enable HTTP/2 protocol support for multiplexed connections."
}

variable "min_tls_version" {
  type        = string
  default     = "1.2"
  description = "Minimum supported TLS version."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Whether public network ingress is allowed for this application."
}

variable "virtual_network_subnet_id" {
  type        = string
  default     = null
  description = "Subnet ID for regional VNet integration to reach private backend resources."
}

variable "vnet_route_all_enabled" {
  type        = bool
  default     = true
  description = "Route all outbound traffic through the integrated VNet."
}

variable "ip_restrictions" {
  type        = list(any)
  default     = []
  description = "List of IP restrictions to apply to the web service ingress."
}

variable "scm_ip_restrictions" {
  type        = list(any)
  default     = []
  description = "List of SCM IP restrictions to apply to the management/deployment endpoint."
}

# -----------------------------------------------------------------------------
# Health Check Configuration
# -----------------------------------------------------------------------------

variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "Path for App Service platform health probes. Unhealthy instances are evicted from routing and recycled."
}

variable "health_check_eviction_time_in_min" {
  type        = number
  default     = 5
  description = "Time in minutes an unhealthy instance can fail health probes before eviction (range: 2 to 10)."
}

# -----------------------------------------------------------------------------
# Rollouts & Deployment Slots
# -----------------------------------------------------------------------------

variable "staging_slot_enabled" {
  type        = bool
  default     = true
  description = "Whether to provision a staging deployment slot for zero-downtime blue/green container rollouts."
}

variable "staging_slot_name" {
  type        = string
  default     = "staging"
  description = "Name of the deployment slot."
}

variable "staging_container_image" {
  type        = string
  default     = null
  description = "Container image for the staging slot. If null, mirrors the production container_image."
}

variable "auto_swap_slot_name" {
  type        = string
  default     = null
  description = "Target slot name for auto-swap upon successful deployment to staging. Set to null for manual/controlled rollout swaps."
}

variable "sticky_app_setting_names" {
  type        = list(string)
  default     = ["ENVIRONMENT", "WEBSITE_RUN_FROM_PACKAGE", "ASPNETCORE_ENVIRONMENT", "NODE_ENV"]
  description = "List of app setting keys that stick to their respective slot during a slot swap."
}

# -----------------------------------------------------------------------------
# Container Registry & Runtime Configuration
# -----------------------------------------------------------------------------

variable "container_port" {
  type        = number
  default     = 8080
  description = "HTTP port the container listens on (passed via WEBSITES_PORT)."
}

variable "container_registry_url" {
  type        = string
  default     = null
  description = "Container registry URL (e.g., 'https://myregistry.azurecr.io'). Leave null for Docker Hub public images."
}

variable "container_registry_use_managed_identity" {
  type        = bool
  default     = false
  description = "Use the App Service Managed Identity to authenticate against the container registry (e.g. Azure Container Registry)."
}

variable "container_registry_username" {
  type        = string
  default     = null
  description = "Username for private container registry when using basic authentication."
}

variable "container_registry_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Password for private container registry when using basic authentication."
}

variable "acr_id" {
  type        = string
  default     = null
  description = "Azure Container Registry resource ID. When provided with container_registry_use_managed_identity, AcrPull role is automatically granted."
}

# -----------------------------------------------------------------------------
# Application Settings & Configuration
# -----------------------------------------------------------------------------

variable "app_settings" {
  type        = map(string)
  default     = {}
  description = "Application environment variables/settings to inject into the production container."
}

variable "staging_app_settings" {
  type        = map(string)
  default     = {}
  description = "Additional or overriding application settings specific to the staging slot."
}

variable "connection_strings" {
  type = map(object({
    type  = string
    value = string
  }))
  default     = {}
  description = "Map of connection strings to configure on the App Service."
}

# -----------------------------------------------------------------------------
# Observability & Monitoring
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Resource ID of the Log Analytics Workspace for centralized logging and diagnostic settings."
}

variable "application_insights_connection_string" {
  type        = string
  default     = null
  sensitive   = true
  description = "Application Insights connection string for APM telemetry."
}

variable "alerts_enabled" {
  type        = bool
  default     = true
  description = "Whether to provision Azure Monitor metric alerts for operational health (5xx errors, latency, CPU, health checks)."
}

variable "action_group_ids" {
  type        = list(string)
  default     = []
  description = "List of Azure Monitor Action Group resource IDs for alert notifications (e.g., PagerDuty, Slack, SRE on-call)."
}

variable "alert_http_5xx_threshold" {
  type        = number
  default     = 10
  description = "HTTP 5xx server error count threshold over 5 minutes to trigger an alert."
}

variable "alert_cpu_threshold" {
  type        = number
  default     = 80
  description = "App Service Plan CPU percentage threshold over 5 minutes to trigger an alert."
}

variable "alert_response_time_threshold_seconds" {
  type        = number
  default     = 2
  description = "Average HTTP response time in seconds over 5 minutes to trigger a latency alert."
}

variable "alert_health_check_threshold" {
  type        = number
  default     = 100
  description = "App Service Health Check percentage threshold. Alert triggers if health status drops below this value."
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Custom resource tags to apply to all resources created by this module."
}
