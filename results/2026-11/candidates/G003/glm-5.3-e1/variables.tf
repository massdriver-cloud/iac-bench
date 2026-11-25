# -----------------------------------------------------------------------------
# Core identity and placement
# -----------------------------------------------------------------------------

variable "name" {
  description = <<-EOT
    Base name for every resource created by this module. The App Service itself
    is named exactly `name`, so it must be globally unique across Azure (it
    becomes `<name>.azurewebsites.net`). 1-35 characters, lowercase letters,
    digits and inner hyphens only, so that derived names such as
    `<name>-plan`, `<name>-law` stay within Azure limits.
  EOT
  type        = string

  validation {
    condition     = length(var.name) <= 35 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be 1-35 characters of lowercase letters, digits and inner hyphens, starting and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region that hosts the service and its supporting resources, e.g. \"westeurope\"."
  type        = string
}

variable "create_resource_group" {
  description = <<-EOT
    When true (default) the module creates a dedicated resource group named
    `<name>-rg`. Set to false to deploy into an existing resource group named
    by `resource_group_name` instead.
  EOT
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into. Required (and only used) when create_resource_group = false."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags merged onto every resource, on top of the module's standard tags."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Capacity & availability
# -----------------------------------------------------------------------------

variable "sku_name" {
  description = <<-EOT
    App Service plan SKU. Standard and above (S1-S3, P1v3-P3v3, EP1-EP3) is
    required for the deployment slot, autoscaling and Always On that this
    module configures. Default: P1v3.
  EOT
  type        = string
  default     = "P1v3"
}

variable "min_instances" {
  description = <<-EOT
    Capacity floor: the minimum number of instances the autoscale profile
    enforces, and the instance count the plan is created with. The autoscale
    engine owns the live instance count from then on. Set min_instances equal
    to max_instances for a fixed-size plan.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1 && var.min_instances == floor(var.min_instances)
    error_message = "min_instances must be a whole number greater than or equal to 1."
  }
}

variable "max_instances" {
  description = "Capacity ceiling: the maximum number of instances the autoscale profile may scale out to."
  type        = number
  default     = 6

  validation {
    condition     = var.max_instances >= 1 && var.max_instances == floor(var.max_instances)
    error_message = "max_instances must be a whole number greater than or equal to 1."
  }
}

# -----------------------------------------------------------------------------
# Container and application configuration
# -----------------------------------------------------------------------------

variable "container_image" {
  description = <<-EOT
    Container image (including tag) the service runs, for example
    myregistry.azurecr.io/team/orders-api:1.4.2 or nginxdemos/hello:latest.
    Update this variable to roll out a new build.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^\\s]+$", var.container_image))
    error_message = "container_image must be a single image reference without whitespace, including its tag."
  }
}

variable "container_registry_url" {
  description = <<-EOT
    Full URL of the registry that serves `container_image`, e.g.
    https://myregistry.azurecr.io or https://ghcr.io. Default: Docker Hub.
    When `acr_resource_id` is set, the default becomes that registry's login
    server (https://<registry-name>.azurecr.io).
  EOT
  type        = string
  default     = null
}

variable "container_registry_username" {
  description = "Registry username, for registries that cannot use managed identity auth (set together with container_registry_password)."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_registry_password" {
  description = "Registry password, for registries that cannot use managed identity auth (set together with container_registry_username)."
  type        = string
  default     = null
  sensitive   = true
}

variable "acr_resource_id" {
  description = <<-EOT
    Resource ID of the Azure Container Registry the image is pulled from. When
    set, the app and its staging slot pull images with their system-assigned
    managed identities: the module enables managed identity registry auth and
    grants both principals AcrPull, so no registry credentials are stored on
    the app.
  EOT
  type        = string
  default     = null
}

variable "app_settings" {
  description = <<-EOT
    App settings (environment variables) for the container, e.g.
    DATABASE_URL, LOG_LEVEL. Values must be strings. Module-owned settings
    (APPLICATIONINSIGHTS_CONNECTION_STRING, WEBSITES_ENABLE_APP_SERVICE_STORAGE)
    are applied on top and win over entries in this map.
  EOT
  type        = map(string)
  default     = {}
}

variable "enable_app_service_storage" {
  description = "Mount the shared Azure SMB storage at /home. Almost always false for stateless API containers; true only for apps that persist files."
  type        = bool
  default     = false
}

variable "websockets_enabled" {
  description = "Enable WebSocket support (needed for subscriptions and other long-lived sockets)."
  type        = bool
  default     = false
}

variable "virtual_network_subnet_id" {
  description = "Subnet ID for VNet integration so the app can reach private backends. The subnet must be delegated to Microsoft.Web. Default: no VNet integration."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Rollouts
# -----------------------------------------------------------------------------

variable "enable_staging_slot" {
  description = "Create a staging deployment slot mirroring production, for blue/green-style rollouts. Default true. Slots share the plan's instances, so this adds no VM cost."
  type        = bool
  default     = true
}

variable "staging_slot_name" {
  description = "Name of the staging deployment slot."
  type        = string
  default     = "staging"

  validation {
    condition     = length(var.staging_slot_name) <= 59 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.staging_slot_name))
    error_message = "staging_slot_name must be 1-59 characters of lowercase letters, digits and inner hyphens."
  }
}

variable "staging_container_image" {
  description = <<-EOT
    Image deployed to the staging slot; defaults to `container_image`. Set a
    candidate build here, apply, and verify it on the staging endpoint (output
    `staging_url`) before promoting it by moving the reference into
    `container_image`.
  EOT
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Log Analytics retention in days for the app's platform, HTTP and console logs (30-730)."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "app_insights_sampling_percentage" {
  description = "Application Insights sampling percentage (0-100). Lower it for high-traffic APIs."
  type        = number
  default     = 100

  validation {
    condition     = var.app_insights_sampling_percentage >= 0 && var.app_insights_sampling_percentage <= 100
    error_message = "app_insights_sampling_percentage must be between 0 and 100."
  }
}

variable "alert_emails" {
  description = "On-call email addresses baseline alerts are delivered to. Leave empty to create no alert wiring; provide at least one address to arm the standard alerts."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "alert_emails must be a list of valid email addresses."
  }
}

variable "action_group_ids" {
  description = "Resource IDs of existing action groups that baseline alerts should also notify (e.g. the team's paging group)."
  type        = list(string)
  default     = []
}

variable "alert_thresholds" {
  description = "Thresholds for the module's baseline alerts: 5xx responses per 5 minutes, minimum average health check score, and plan CPU percentage."
  type = object({
    http_5xx_per_5m = optional(number, 20)
    health_score    = optional(number, 90)
    cpu_percent     = optional(number, 85)
  })
  default = {}
}
