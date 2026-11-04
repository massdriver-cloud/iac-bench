# -----------------------------------------------------------------------------
# Identity of the service
# -----------------------------------------------------------------------------

variable "name" {
  description = "Short service name (e.g. \"orders-api\"). Used to name every resource this module creates. Must be globally unique-ish: the App Service hostname app-<name>.azurewebsites.net must be unique across Azure."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 chars of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create (and own) for this service. One resource group per service keeps lifecycle, RBAC and billing clean."
  type        = string
}

variable "location" {
  description = "Azure region for all resources (e.g. \"westeurope\")."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource. A \"service\" tag with var.name is always added."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Capacity
# -----------------------------------------------------------------------------

variable "sku_name" {
  description = "App Service Plan SKU. Premium v3 is the default because it supports zone redundancy, slots, autoscaling and has predictable performance. Standard (S*) works if you do not need zone redundancy."
  type        = string
  default     = "P1v3"

  validation {
    condition     = can(regex("^(B[1-3]|S[1-3]|P[1-3]v2|P[0-3]v3|P[1-5]mv3|I[1-3]|I[1-6]v2)$", var.sku_name))
    error_message = "sku_name must be a paid Linux App Service SKU (B1-B3, S1-S3, P1v2-P3v2, P0v3-P3v3, P1mv3-P5mv3, I1-I3, I1v2-I6v2). Free/Shared SKUs are not supported by this module (no slots, no autoscale, no always-on)."
  }
}

variable "capacity" {
  description = "Number of plan instances (workers) when autoscaling is off. When zone_redundant = true this is raised to at least 3 automatically. If autoscaling is enabled, keep this aligned with autoscale.default_capacity."
  type        = number
  default     = 1

  validation {
    condition     = var.capacity >= 1 && var.capacity <= 30
    error_message = "capacity must be between 1 and 30 instances."
  }
}

variable "zone_redundant" {
  description = "Spread plan instances across availability zones. Requires a Premium (v2/v3) or Isolated v2 SKU and at least 3 instances - the module raises capacity to 3 automatically when enabled."
  type        = bool
  default     = false
}

variable "autoscale" {
  description = <<-EOT
    CPU/memory driven autoscaling for the App Service Plan. When disabled the plan
    runs a fixed `capacity`. Thresholds are percentages averaged over 10 minutes.
  EOT
  type = object({
    enabled                    = optional(bool, false)
    minimum                    = optional(number, 1)
    maximum                    = optional(number, 6)
    default_capacity           = optional(number, 1)
    scale_out_cpu_threshold    = optional(number, 70)
    scale_in_cpu_threshold     = optional(number, 35)
    scale_out_memory_threshold = optional(number, 80)
    scale_in_memory_threshold  = optional(number, 50)
  })
  default = {}
}

# -----------------------------------------------------------------------------
# Container
# -----------------------------------------------------------------------------

variable "container" {
  description = <<-EOT
    Container to run.

    image                - image reference including the tag, without the registry host (e.g. "myapp/api:1.4.2").
    registry_url         - registry server URL (e.g. "https://myregistry.azurecr.io").
    registry_username /  - basic auth credentials for private registries that do not
    registry_password      support managed identity pulls. Leave null otherwise.
    use_managed_identity - pull the image using the app identity instead of passwords
                           (recommended for ACR). Grant pulls via registry_id.
    identity_client_id   - client id of a user-assigned identity to pull with; only
                           needed when use_managed_identity = true and the app uses a
                           user-assigned identity.
    registry_id          - resource id of an Azure Container Registry. When set, the
                           module grants the app system-assigned identity AcrPull on it.
    port                 - port the container listens on if not 80/8080 (sets WEBSITES_PORT).
  EOT
  type = object({
    image                = string
    registry_url         = optional(string, "https://mcr.microsoft.com")
    registry_username    = optional(string)
    registry_password    = optional(string)
    use_managed_identity = optional(bool, false)
    identity_client_id   = optional(string)
    registry_id          = optional(string)
    port                 = optional(number)
  })
  sensitive = true
}

variable "app_settings" {
  description = "Extra app settings (environment variables) for the service. Merged over the module-managed settings (observability, container port) - your values win on conflict."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Health
# -----------------------------------------------------------------------------

variable "health_check_path" {
  description = "HTTP path App Service polls on every instance (e.g. \"/health\"). Unhealthy instances are removed from the load balancer and replaced. Set to null to disable."
  type        = string
  default     = "/health"
}

variable "health_check_eviction_time_in_minutes" {
  description = "Minutes an instance may fail the health check before it is removed and replaced (2-10)."
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_eviction_time_in_minutes >= 2 && var.health_check_eviction_time_in_minutes <= 10
    error_message = "health_check_eviction_time_in_minutes must be between 2 and 10."
  }
}

variable "auto_heal" {
  description = <<-EOT
    Auto-heal: recycle the worker process automatically when the app misbehaves.
    Defaults: recycle when >10 responses in the 500-530 range are seen within
    5 minutes, or when >10 requests take longer than 30s within 5 minutes.
    Set request_count to enable recycling after N total requests (useful for
    slow memory leaks). Set any *_count to null to disable that trigger.
  EOT
  type = object({
    enabled               = optional(bool, true)
    status_code_range     = optional(string, "500-530")
    status_code_count     = optional(number, 10)
    status_code_interval  = optional(string, "00:05:00")
    slow_request_time     = optional(string, "00:00:30")
    slow_request_count    = optional(number, 10)
    slow_request_interval = optional(string, "00:05:00")
    request_count         = optional(number)
    request_interval      = optional(string, "00:05:00")
  })
  default = {}
}

# -----------------------------------------------------------------------------
# Rollouts (blue/green via a deployment slot)
# -----------------------------------------------------------------------------

variable "deployment_slot" {
  description = <<-EOT
    Blue/green rollouts. The module creates a slot (default "staging") that mirrors
    the production configuration. Deploy the candidate build to the slot, warm it up,
    then set promote_to_production = true and apply to swap it into production.
    Setting promote_to_production back to false and applying swaps back (rollback).
  EOT
  type = object({
    enabled               = optional(bool, true)
    name                  = optional(string, "staging")
    promote_to_production = optional(bool, false)
  })
  default = {}
}

variable "sticky_app_setting_names" {
  description = "App setting names that stay with a slot during swaps (\"slot settings\"), e.g. environment-specific values like [\"ASPNETCORE_ENVIRONMENT\"]."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Identity & networking
# -----------------------------------------------------------------------------

variable "identity_type" {
  description = "Managed identity type for the app: SystemAssigned (default), UserAssigned, or \"SystemAssigned, UserAssigned\"."
  type        = string
  default     = "SystemAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.identity_type)
    error_message = "identity_type must be one of: SystemAssigned, UserAssigned, \"SystemAssigned, UserAssigned\"."
  }
}

variable "identity_ids" {
  description = "Resource ids of user-assigned managed identities to attach (when identity_type includes UserAssigned)."
  type        = list(string)
  default     = []
}

variable "vnet_integration_subnet_id" {
  description = "Subnet id for regional VNet integration (outbound). Subnet must be delegated to Microsoft.Web/serverFarms. Null keeps the app on public outbound."
  type        = string
  default     = null
}

variable "vnet_route_all_enabled" {
  description = "Route all outbound traffic through the VNet integration (otherwise only RFC1918 traffic is routed)."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow inbound traffic from the public internet. Set false when the service sits behind a private ingress (Front Door with Private Link, internal APIM, ...)."
  type        = bool
  default     = true
}

variable "websockets_enabled" {
  description = "Enable WebSockets (SignalR, socket.io, ...). Off by default for plain HTTP APIs."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "application_insights_enabled" {
  description = "Create a workspace-based Application Insights resource and wire its connection string into the app settings."
  type        = bool
  default     = true
}

variable "diagnostic_logs_enabled" {
  description = "Send App Service logs (HTTP, console, app, audit, platform) and metrics of the app, slot and plan to Log Analytics."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace id to send diagnostics to and to back Application Insights. Null = the module creates a dedicated workspace."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention of the Log Analytics workspace the module creates (ignored when log_analytics_workspace_id is provided)."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "availability_test" {
  description = "External availability monitoring: an Application Insights standard web test that probes the health endpoint from outside Azure's load balancer and feeds an availability metric alert."
  type = object({
    enabled           = optional(bool, true)
    locations         = optional(list(string), ["us-va-ash-azr"])
    frequency_seconds = optional(number, 300)
    timeout_seconds   = optional(number, 30)
  })
  default = {}
}

variable "alerts" {
  description = <<-EOT
    Metric alerts. Every alert is wired to all action groups: the ones this module
    creates from email_receivers plus any existing ones passed via action_group_ids.

    http5xx_threshold               - total HTTP 5xx responses in 5 minutes.
    response_time_threshold_seconds - average server response time over 5 minutes.
    health_check_threshold          - average HealthCheckStatus (100 = all instances
                                      healthy); alert fires when it drops below.
    availability_threshold          - average availability percentage of the external
                                      web test over 15 minutes.
    cpu/memory_threshold_percent    - plan-level CPU/memory averaged over 15 minutes
                                      (catches saturation at max scale).
  EOT
  type = object({
    enabled                         = optional(bool, true)
    action_group_ids                = optional(list(string), [])
    email_receivers                 = optional(list(string), [])
    http5xx_threshold               = optional(number, 25)
    response_time_threshold_seconds = optional(number, 2)
    health_check_threshold          = optional(number, 100)
    availability_threshold          = optional(number, 100)
    cpu_threshold_percent           = optional(number, 85)
    memory_threshold_percent        = optional(number, 85)
  })
  default = {}
}
