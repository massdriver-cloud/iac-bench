# -----------------------------------------------------------------------------
# Core Service Identity & Placement (Required)
# -----------------------------------------------------------------------------

variable "name" {
  description = "Logical name of the service (e.g., 'orders-api'). Used to derive Azure resource names and standard tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$", var.name))
    error_message = "var.name must be 1-40 characters of lowercase letters, numbers, and hyphens, starting and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment identifier (e.g., 'prod', 'staging', 'dev')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", var.environment))
    error_message = "var.environment must be 1-16 characters of lowercase letters, numbers, and hyphens, starting and ending with an alphanumeric character."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed (e.g., 'eastus2', 'westeurope')."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "var.location must not be empty."
  }
}

variable "container" {
  description = <<-EOT
    Container workload configuration for the HTTP service:
    - image: Container image repository and tag/digest without registry host (e.g., 'orders-api:1.4.2' or 'library/nginx:1.27-alpine').
    - registry_url: Full HTTPS URL of the container registry (defaults to Docker Hub; e.g., 'https://myacr.azurecr.io').
    - port: HTTP TCP port exposed by the container (wired to WEBSITES_PORT).
    - command: Optional container startup command override.
    - acr_id: Optional Azure Container Registry resource ID; when set, enables Managed Identity pull and grants AcrPull to the System-Assigned identity of the app and staging slot (when managed_identity_client_id is null).
    - use_managed_identity_auth: Pull image from ACR using Managed Identity (automatically enabled when acr_id is provided).
    - managed_identity_client_id: Optional client ID of a User-Assigned Managed Identity for ACR authentication (defaults to System-Assigned identity).
    - registry_username: Optional username for non-Managed-Identity private registries (supply password via var.container_registry_password).
    - enable_persistent_storage: Mounts App Service /home SMB storage into the container (defaults to false for stateless APIs).
    - websockets_enabled: Enable WebSocket protocol upgrades at the App Service front end.
  EOT
  type = object({
    image                      = string
    registry_url               = optional(string, "https://index.docker.io")
    port                       = optional(number, 8080)
    command                    = optional(string)
    acr_id                     = optional(string)
    use_managed_identity_auth  = optional(bool, false)
    managed_identity_client_id = optional(string)
    registry_username          = optional(string)
    enable_persistent_storage  = optional(bool, false)
    websockets_enabled         = optional(bool, false)
  })

  validation {
    condition     = length(trimspace(var.container.image)) > 0
    error_message = "container.image must be a non-empty image reference (e.g., 'myservice:1.0.0')."
  }

  validation {
    condition     = can(regex("^https://", var.container.registry_url))
    error_message = "container.registry_url must start with 'https://' (e.g., 'https://myacr.azurecr.io')."
  }

  validation {
    condition     = var.container.port >= 1 && var.container.port <= 65535 && floor(var.container.port) == var.container.port
    error_message = "container.port must be a valid TCP port integer between 1 and 65535."
  }
}

# -----------------------------------------------------------------------------
# Resource Group & Naming Options
# -----------------------------------------------------------------------------

variable "create_resource_group" {
  description = "Whether this module should create and manage the Azure Resource Group. Set to false to deploy into an existing resource group."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Override the Resource Group name. Defaults to 'rg-<name>-<environment>'. Required when create_resource_group is false if using a custom name."
  type        = string
  default     = null
}

variable "use_random_name_suffix" {
  description = "Append a deterministic 6-character random suffix to globally-scoped resource names (e.g., the *.azurewebsites.net Web App name) to prevent global DNS collisions."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional resource tags merged onto standard SRE module tags (service, environment, managed_by)."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Application Configuration, Identity & Secrets
# -----------------------------------------------------------------------------

variable "app_settings" {
  description = "Non-sensitive environment variables injected into the container."
  type        = map(string)
  default     = {}
}

variable "secret_app_settings" {
  description = "Sensitive environment variables injected directly into the container (prefer key_vault_secret_uris where possible)."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "container_registry_password" {
  description = "Password or token for authenticating to a private container registry when Managed Identity is not used."
  type        = string
  default     = null
  sensitive   = true
}

variable "key_vault_secret_uris" {
  description = "Map of environment variable names to Azure Key Vault Secret URIs (automatically wrapped as @Microsoft.KeyVault(SecretUri=...))."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for uri in values(var.key_vault_secret_uris) : can(regex("^https://[^/]+/secrets/[^/]+", uri))])
    error_message = "Every value in key_vault_secret_uris must be a valid Azure Key Vault secret URI (e.g., 'https://mykv.vault.azure.net/secrets/db-password')."
  }
}

variable "key_vault_id" {
  description = "Optional Azure Key Vault resource ID. When set (and key_vault_reference_identity_id is null), grants 'Key Vault Secrets User' RBAC role to the Web App and staging slot System-Assigned Managed Identities."
  type        = string
  default     = null
}

variable "key_vault_reference_identity_id" {
  description = "Optional User-Assigned Managed Identity resource ID used to resolve Key Vault references. Defaults to the System-Assigned identity."
  type        = string
  default     = null
}

variable "user_assigned_identity_ids" {
  description = "Optional set of User-Assigned Managed Identity resource IDs to attach alongside the System-Assigned identity."
  type        = set(string)
  default     = []
}

variable "connection_strings" {
  description = "Map of named App Service connection strings (key = connection name, type = SQLAzure/Custom/PostgreSQL/MySql/RedisCache/etc., value = connection string)."
  type = map(object({
    type  = string
    value = string
  }))
  default   = {}
  sensitive = true
}

# -----------------------------------------------------------------------------
# Capacity & Autoscaling
# -----------------------------------------------------------------------------

variable "capacity" {
  description = <<-EOT
    Compute capacity and horizontal autoscaling policy:
    - existing_service_plan_id: Optional ID of a shared Linux App Service Plan; when null, creates a dedicated plan.
    - sku_name: App Service Plan SKU (defaults to 'P1v3' for production-grade VNet, slot, and autoscale support).
    - min_instances: Baseline / minimum worker instance count.
    - max_instances: Maximum worker instance count. When greater than min_instances on a module-managed Standard/Premium/Isolated plan, horizontal autoscaling is configured automatically.
    - per_site_scaling_enabled: Enable per-app worker limits independent of total App Service Plan instance count.
    - autoscale: Thresholds and evaluation windows for CPU, Memory, and HTTP queue horizontal scaling.
  EOT
  type = object({
    existing_service_plan_id = optional(string)
    sku_name                 = optional(string, "P1v3")
    min_instances            = optional(number, 2)
    max_instances            = optional(number, 6)
    per_site_scaling_enabled = optional(bool, false)
    autoscale = optional(object({
      enabled                    = optional(bool, true)
      cpu_scale_out_percent      = optional(number, 70)
      cpu_scale_in_percent       = optional(number, 35)
      memory_scale_out_percent   = optional(number, 80)
      memory_scale_in_percent    = optional(number, 50)
      http_queue_scale_out_count = optional(number, 100)
      scale_out_window_minutes   = optional(number, 5)
      scale_out_cooldown_minutes = optional(number, 5)
      scale_in_window_minutes    = optional(number, 10)
      scale_in_cooldown_minutes  = optional(number, 10)
    }), {})
  })
  default = {}

  validation {
    condition = contains([
      "F1",
      "B1", "B2", "B3",
      "S1", "S2", "S3",
      "P1v2", "P2v2", "P3v2",
      "P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3",
      "P0v4", "P1v4", "P2v4", "P3v4", "P1mv4", "P2mv4", "P3mv4", "P4mv4", "P5mv4",
      "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2"
    ], var.capacity.sku_name)
    error_message = "capacity.sku_name must be a valid Linux App Service Plan SKU (e.g., 'B1', 'S1', 'P0v3', 'P1v3', 'P2v3', 'P1v4', 'I1v2')."
  }

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances && var.capacity.max_instances <= 30
    error_message = "capacity.min_instances must be >= 1 and capacity.max_instances must be between min_instances and 30."
  }

  validation {
    condition = (
      var.capacity.autoscale.cpu_scale_in_percent < var.capacity.autoscale.cpu_scale_out_percent &&
      var.capacity.autoscale.memory_scale_in_percent < var.capacity.autoscale.memory_scale_out_percent
    )
    error_message = "Autoscale scale-in percentages must be strictly lower than scale-out percentages to prevent flapping."
  }
}

# -----------------------------------------------------------------------------
# Availability & Transport Hardening
# -----------------------------------------------------------------------------

variable "availability" {
  description = <<-EOT
    Availability, resiliency, and transport hardening controls:
    - zone_redundant: Spread App Service Plan workers across Azure Availability Zones (requires Premium v2/v3/v4 [excluding P0] or Isolated v2 SKU and min_instances >= 2).
    - always_on: Prevent container idle unload / cold starts (automatically disabled on F1 SKU).
    - client_affinity_enabled: ARR session affinity cookies (defaults to false for stateless HTTP APIs).
    - https_only: Redirect all HTTP requests to HTTPS.
    - http2_enabled: Enable HTTP/2 protocol support.
    - minimum_tls_version: Minimum accepted TLS version ('1.2' or '1.3') for both main and SCM endpoints.
  EOT
  type = object({
    zone_redundant          = optional(bool, false)
    always_on               = optional(bool, true)
    client_affinity_enabled = optional(bool, false)
    https_only              = optional(bool, true)
    http2_enabled           = optional(bool, true)
    minimum_tls_version     = optional(string, "1.2")
  })
  default = {}

  validation {
    condition     = contains(["1.2", "1.3"], var.availability.minimum_tls_version)
    error_message = "availability.minimum_tls_version must be '1.2' or '1.3' (TLS 1.0/1.1 are rejected by policy)."
  }
}

# -----------------------------------------------------------------------------
# Health Probing & Startup Lifecycle
# -----------------------------------------------------------------------------

variable "health" {
  description = <<-EOT
    Container health probing, eviction, and startup lifecycle:
    - path: HTTP GET path probed by App Service Health Check and slot warmup (set to null to disable health probing).
    - eviction_time_in_min: Minutes an unhealthy worker fails probes before eviction from the load balancer (2-10).
    - startup_timeout_seconds: Maximum seconds App Service waits for the container port to respond on startup (30-1800).
    - warmup_valid_status_codes: Comma-separated HTTP status codes accepted as healthy during slot swap warmup.
  EOT
  type = object({
    path                      = optional(string, "/healthz")
    eviction_time_in_min      = optional(number, 5)
    startup_timeout_seconds   = optional(number, 230)
    warmup_valid_status_codes = optional(string, "200")
  })
  default = {}

  validation {
    condition     = var.health.path == null || can(regex("^/", var.health.path))
    error_message = "health.path must start with '/' (e.g., '/healthz') or be null."
  }

  validation {
    condition     = var.health.eviction_time_in_min >= 2 && var.health.eviction_time_in_min <= 10
    error_message = "health.eviction_time_in_min must be between 2 and 10 minutes."
  }

  validation {
    condition     = var.health.startup_timeout_seconds >= 30 && var.health.startup_timeout_seconds <= 1800
    error_message = "health.startup_timeout_seconds must be between 30 and 1800 seconds."
  }
}

# -----------------------------------------------------------------------------
# Rollouts & Deployment Slots
# -----------------------------------------------------------------------------

variable "rollout" {
  description = <<-EOT
    Zero-downtime rollout and deployment slot strategy:
    - staging_slot_enabled: Provision a pre-production deployment slot with warmup probes mirrored from production (requires Standard, Premium, or Isolated SKU).
    - slot_name: Name of the pre-production slot (defaults to 'staging').
    - auto_swap_enabled: Automatically swap the staging slot into production once warmup and health checks succeed.
    - slot_app_settings_override: Environment variables specific to the staging slot (automatically pinned as slot-sticky settings so they never leak into production on swap).
    - sticky_app_setting_names: Additional app setting keys pinned to slots across swaps.
    - sticky_connection_string_names: Connection string names pinned to slots across swaps.
  EOT
  type = object({
    staging_slot_enabled           = optional(bool, true)
    slot_name                      = optional(string, "staging")
    auto_swap_enabled              = optional(bool, false)
    slot_app_settings_override     = optional(map(string), {})
    sticky_app_setting_names       = optional(list(string), [])
    sticky_connection_string_names = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$", var.rollout.slot_name))
    error_message = "rollout.slot_name must be 1-20 characters of lowercase letters, numbers, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Observability: Telemetry, Logs & Golden-Signal Alerting
# -----------------------------------------------------------------------------

variable "observability" {
  description = <<-EOT
    Telemetry, centralized logging, and golden-signal alerting:
    - enabled: Master toggle for the observability stack (Log Analytics, App Insights, Diagnostics, Alerts).
    - existing_log_analytics_workspace_id: Existing Log Analytics Workspace ID; when null, provisions a dedicated workspace.
    - log_retention_days: Retention period (30-730 days) when creating a Log Analytics Workspace.
    - application_insights_enabled: Provision workspace-based Application Insights and inject APPLICATIONINSIGHTS_CONNECTION_STRING.
    - sampling_percentage: Application Insights telemetry ingestion sampling percentage (0-100).
    - diagnostic_logs_enabled: Stream HTTP, console, app, platform, and audit logs plus metrics to Log Analytics.
    - action_group_ids: Existing Azure Monitor Action Group resource IDs notified on alerts.
    - alert_emails: Optional list of email addresses; when non-empty, creates a dedicated Action Group attached to all service alerts.
    - alerts: Thresholds and severities for golden-signal Azure Monitor metric alerts (HTTP 5xx, latency, health check degradation, and plan CPU/memory saturation).
  EOT
  type = object({
    enabled                             = optional(bool, true)
    existing_log_analytics_workspace_id = optional(string)
    log_retention_days                  = optional(number, 30)
    application_insights_enabled        = optional(bool, true)
    sampling_percentage                 = optional(number, 100)
    diagnostic_logs_enabled             = optional(bool, true)
    action_group_ids                    = optional(list(string), [])
    alert_emails                        = optional(list(string), [])
    alerts = optional(object({
      enabled                             = optional(bool, true)
      http_5xx_threshold                  = optional(number, 10)
      http_5xx_severity                   = optional(number, 1)
      response_time_seconds_threshold     = optional(number, 2.0)
      response_time_severity              = optional(number, 2)
      health_check_degraded_threshold_pct = optional(number, 99)
      health_check_severity               = optional(number, 1)
      cpu_high_percent_threshold          = optional(number, 85)
      memory_high_percent_threshold       = optional(number, 85)
      saturation_severity                 = optional(number, 2)
    }), {})
  })
  default = {}

  validation {
    condition     = var.observability.log_retention_days >= 30 && var.observability.log_retention_days <= 730
    error_message = "observability.log_retention_days must be between 30 and 730 days."
  }

  validation {
    condition     = var.observability.sampling_percentage >= 0 && var.observability.sampling_percentage <= 100
    error_message = "observability.sampling_percentage must be between 0 and 100."
  }
}

# -----------------------------------------------------------------------------
# Networking, Ingress Restrictions & CORS
# -----------------------------------------------------------------------------

variable "networking" {
  description = <<-EOT
    Network integration, ingress restrictions, and CORS:
    - vnet_integration_subnet_id: Delegated Microsoft.Web/serverFarms subnet ID for regional outbound VNet integration.
    - vnet_route_all_enabled: Route all outbound traffic through the integrated VNet.
    - vnet_image_pull_enabled: Pull container images over the integrated VNet (defaults to true when vnet_integration_subnet_id is set).
    - public_network_access_enabled: Enable public network ingress on the Web App and staging slot.
    - ip_restriction_default_action: Default action ('Allow' or 'Deny') when no IP restriction rule matches (automatically 'Deny' when front_door_id, allowed_cidrs, or allowed_subnet_ids are set unless explicitly overridden).
    - front_door_id: Optional Azure Front Door profile UUID (X-Azure-FDID); restricts ingress exclusively to that Front Door instance via AzureFrontDoor.Backend service tag.
    - allowed_cidrs: Optional list of IPv4/IPv6 CIDR blocks permitted inbound.
    - allowed_subnet_ids: Optional list of VNet Subnet IDs permitted inbound via Service Endpoints.
    - scm_use_main_ip_restriction: Mirror main site IP restrictions onto the SCM/Kudu deployment endpoint.
    - scm_allowed_cidrs: Optional list of CIDR blocks allowed to reach SCM/Kudu when scm_use_main_ip_restriction is false.
    - cors: Optional CORS policy for browser-facing HTTP APIs.
  EOT
  type = object({
    vnet_integration_subnet_id    = optional(string)
    vnet_route_all_enabled        = optional(bool, true)
    vnet_image_pull_enabled       = optional(bool)
    public_network_access_enabled = optional(bool, true)
    ip_restriction_default_action = optional(string)
    front_door_id                 = optional(string)
    allowed_cidrs                 = optional(list(string), [])
    allowed_subnet_ids            = optional(list(string), [])
    scm_use_main_ip_restriction   = optional(bool, false)
    scm_allowed_cidrs             = optional(list(string), [])
    cors = optional(object({
      allowed_origins     = list(string)
      support_credentials = optional(bool, false)
    }))
  })
  default = {}

  validation {
    condition     = var.networking.ip_restriction_default_action == null || contains(["Allow", "Deny"], var.networking.ip_restriction_default_action)
    error_message = "networking.ip_restriction_default_action must be 'Allow', 'Deny', or null."
  }

  validation {
    condition     = var.networking.front_door_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.networking.front_door_id))
    error_message = "networking.front_door_id must be a valid UUID matching the Azure Front Door profile X-Azure-FDID."
  }
}
