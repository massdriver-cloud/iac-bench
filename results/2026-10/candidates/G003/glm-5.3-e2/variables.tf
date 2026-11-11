# -----------------------------------------------------------------------------
# Service identity and workload
# -----------------------------------------------------------------------------

variable "name" {
  type = string
  description = <<-EOT
    Name of the service. Used verbatim as the App Service name (and therefore as
    the leftmost label of the `<name>.azurewebsites.net` hostname, which must be
    globally unique) and as the prefix for every supporting resource the module
    creates: `<name>-rg`, `<name>-plan`, `<name>-law`, `<name>-ai`.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "The name must be 3-30 characters, use only lowercase letters, digits and hyphens, and start and end with an alphanumeric character."
  }
}

variable "location" {
  type = string
  description = <<-EOT
    Azure region the service runs in. Every resource created by the module is
    placed in this region. When `resource_group_name` points at an existing
    resource group, this region should normally match it.
  EOT
}

variable "resource_group_name" {
  type    = string
  default = null
  description = <<-EOT
    Existing resource group to deploy into. Leave unset (default) and the module
    creates - and owns - a dedicated resource group named `<name>-rg`, which is
    the recommended shape: one resource group per service.
  EOT
}

variable "image" {
  type = object({
    name                 = string
    tag                  = optional(string, "latest")
    port                 = optional(number)
    startup_command      = optional(string)
    registry_url         = optional(string)
    registry_id          = optional(string)
    registry_username    = optional(string)
    registry_password    = optional(string)
    use_managed_identity = optional(bool, false)
  })
  sensitive = true
  description = <<-EOT
    The container image the service runs, and how App Service authenticates to
    its registry. Changing `tag` is how a new version is released.

    `name`    - image reference without the tag, e.g. `ghcr.io/acme/orders-api`.
    `tag`     - image tag to run, e.g. `v2.4.0`.
    `port`    - port the container listens on (sets `WEBSITES_PORT`); leave unset
                when the image listens on 80.
    `startup_command` - optional startup file/command for the container.
    `registry_url` - login server of a private registry, e.g.
                `https://acme.azurecr.io`. Omit for public Docker Hub images.
    `registry_id`  - ARM resource id of an Azure Container Registry. When
                `use_managed_identity` is true and this is set, the module
                grants `AcrPull` on that registry to the managed identity of the
                app and of every deployment slot.
    `registry_username` / `registry_password` - basic auth fallback for
                registries without managed identity support. Prefer managed
                identity for ACR.
    `use_managed_identity` - pull the image using the app's system-assigned
                managed identity. Recommended for ACR: also set `registry_url`
                and `registry_id` (the latter gets the role assignment created).

    The whole variable is sensitive because it can carry a registry password;
    only the password is actually secret.
  EOT

  validation {
    condition     = length(var.image.name) > 0
    error_message = "image.name must not be empty."
  }

  validation {
    condition     = var.image.port == null || (var.image.port >= 1 && var.image.port <= 65535)
    error_message = "image.port must be a TCP port between 1 and 65535."
  }
}

variable "app_settings" {
  type      = map(string)
  default   = {}
  sensitive = true
  description = <<-EOT
    Environment variables (app settings) for the service, applied to production
    and to every deployment slot. Marked sensitive because app settings
    frequently carry secrets - prefer Key Vault references where possible.

    The module reserves and always wins on these keys:
    `APPLICATIONINSIGHTS_CONNECTION_STRING`, `APPINSIGHTS_INSTRUMENTATIONKEY`,
    `WEBSITES_ENABLE_APP_SERVICE_STORAGE` and `WEBSITES_PORT`.
  EOT
}

variable "connection_strings" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string, "Custom")
  }))
  default     = []
  sensitive   = true
  description = <<-EOT
    Connection strings for the service, applied to production and to every
    deployment slot. They swap with deployments; mark individual names as
    slot-sticky via `rollout.sticky_connection_string_names` if a slot needs its
    own value.
  EOT

  validation {
    condition = alltrue([
      for cs in var.connection_strings :
      contains(["APIHub", "Custom", "DocDb", "EventHub", "MySQL", "NotificationHub", "PostgreSQL", "RedisCache", "ServiceBus", "SQLAzure", "SQLServer"], cs.type)
    ])
    error_message = "connection_strings[].type must be one of: APIHub, Custom, DocDb, EventHub, MySQL, NotificationHub, PostgreSQL, RedisCache, ServiceBus, SQLAzure, SQLServer."
  }
}

# -----------------------------------------------------------------------------
# Capacity and availability
# -----------------------------------------------------------------------------

variable "capacity" {
  type = object({
    instance_size            = optional(string, "P1v3")
    min_instances            = optional(number, 3)
    max_instances            = optional(number, 6)
    scale_out_cpu_percent    = optional(number, 70)
    scale_in_cpu_percent     = optional(number, 30)
    scale_out_memory_percent = optional(number, 80)
    notification_emails      = optional(list(string), [])
  })
  default = {}
  description = <<-EOT
    How much compute the service gets and when it scales. This is also the
    module's availability floor: the plan runs `min_instances` always-on
    instances, and Premium plans with 3 or more instances are what App Service
    spreads across availability zones in zone-capable regions - hence the
    default of 3.

    `instance_size` - App Service plan SKU, e.g. `P1v3`, `P2v3`, `S1`, `B1`.
    `min_instances` - instances the plan always runs.
    `max_instances` - autoscale ceiling. Autoscaling (CPU and memory driven
                scale-out, CPU driven scale-in) is enabled whenever
                `max_instances > min_instances`; set it equal to `min_instances`
                to pin a fixed size. Autoscaling requires Standard or above.
    `scale_out_cpu_percent` / `scale_out_memory_percent` - average plan CPU /
                memory above which one instance is added (5 minute cooldown).
    `scale_in_cpu_percent` - average plan CPU below which one instance is
                removed (10 minute cooldown).
    `notification_emails` - addresses notified on autoscale events.

    Note: the plan's worker count is set from `min_instances`; if autoscaling
    has scaled out, a subsequent `tofu apply` first returns the plan to
    `min_instances` before autoscale scales it out again.
  EOT

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.min_instances <= 100
    error_message = "capacity.min_instances must be between 1 and 100."
  }

  validation {
    condition     = var.capacity.max_instances == null || var.capacity.max_instances >= var.capacity.min_instances
    error_message = "capacity.max_instances must be greater than or equal to capacity.min_instances; set it equal to min_instances to pin a fixed size."
  }

  validation {
    condition = (
      var.capacity.scale_in_cpu_percent >= 0 && var.capacity.scale_in_cpu_percent <= 100 &&
      var.capacity.scale_out_cpu_percent >= 1 && var.capacity.scale_out_cpu_percent <= 100 &&
      var.capacity.scale_out_memory_percent >= 1 && var.capacity.scale_out_memory_percent <= 100 &&
      var.capacity.scale_in_cpu_percent < var.capacity.scale_out_cpu_percent
    )
    error_message = "capacity thresholds must be percentages between 0 and 100, with scale_in_cpu_percent strictly below scale_out_cpu_percent."
  }
}

# -----------------------------------------------------------------------------
# Health
# -----------------------------------------------------------------------------

variable "health" {
  type = object({
    enabled          = optional(bool, true)
    path             = optional(string, "/healthz")
    eviction_minutes = optional(number, 5)
  })
  default = {}
  description = <<-EOT
    Liveness contract between the service and App Service.

    App Service probes `path` on every instance; instances that fail it are
    removed from the load balancer and, after `eviction_minutes` of continued
    failure, evicted and replaced. Unhealthy instances stop receiving traffic
    during rollouts and crashes instead of serving it. The endpoint must return
    200 to the probe and should stay cheap.

    `enabled` - set false only for images that cannot expose any endpoint.
  EOT

  validation {
    condition     = !var.health.enabled || can(regex("^/", var.health.path))
    error_message = "health.path must be an absolute path starting with '/'."
  }

  validation {
    condition     = var.health.eviction_minutes >= 2 && var.health.eviction_minutes <= 10
    error_message = "health.eviction_minutes must be between 2 and 10."
  }
}

# -----------------------------------------------------------------------------
# Rollout
# -----------------------------------------------------------------------------

variable "rollout" {
  type = object({
    slots = optional(list(object({
      name      = string
      image_tag = optional(string)
    })), [{ name = "staging" }])
    sticky_app_setting_names       = optional(list(string), [])
    sticky_connection_string_names = optional(list(string), [])
  })
  default = {}
  description = <<-EOT
    How new versions reach production: a warm, identically configured staging
    slot per app, plus the stickiness rules that make swaps safe.

    `slots` - deployment slots to create. Each slot mirrors production (same
    plan, image, settings, health check, identity, diagnostics) and gets its own
    App Insights component, so pre-production traffic is never mixed with
    production telemetry. Set `image_tag` on a slot to run a candidate version
    there before promoting it (see the rollout runbook in the README).

    `sticky_app_setting_names` / `sticky_connection_string_names` - additional
    settings that must stay with a slot instead of swapping with deployments.
    The module already pins the App Insights settings; add anything else that
    differs per slot.

    The module does not manage slot swaps or traffic weights
    (`az webapp deployment slot swap` / `az webapp traffic-routing set`) because
    those are rollout-time operations, not infrastructure.
  EOT

  validation {
    condition     = alltrue([for slot in var.rollout.slots : can(regex("^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$", slot.name))])
    error_message = "Slot names must be 1-20 characters: lowercase letters, digits and hyphens, starting and ending with an alphanumeric character."
  }

  validation {
    condition     = alltrue([for slot in var.rollout.slots : lower(slot.name) != "production"])
    error_message = "'production' is reserved for the production slot itself."
  }

  validation {
    condition     = length(distinct([for slot in var.rollout.slots : slot.name])) == length(var.rollout.slots)
    error_message = "Slot names must be unique."
  }
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "observability" {
  type = object({
    workspace_id      = optional(string)
    retention_in_days = optional(number, 30)
    log_categories = optional(list(string), [
      "AppServiceHTTPLogs",
      "AppServiceConsoleLogs",
      "AppServiceAppLogs",
      "AppServiceAuditLogs",
      "AppServiceIPSecAuditLogs",
      "AppServicePlatformLogs",
    ])
    app_insights = optional(object({
      sampling_percentage = optional(number, 100)
      disable_ip_masking  = optional(bool, false)
    }), {})
  })
  default = {}
  description = <<-EOT
    Telemetry pipeline for the service.

    By default the module creates a dedicated Log Analytics workspace
    (`<name>-law`) and streams every App Service log category (platform, HTTP,
    console/stdout, app, audit) into resource-specific tables, plus a
    workspace-based App Insights component (`<name>-ai`, and one per deployment
    slot) wired into the app through `APPLICATIONINSIGHTS_CONNECTION_STRING`.
    Pass `workspace_id` to reuse an existing workspace instead of creating one.

    `retention_in_days` - workspace retention (30-730, or -1 for unlimited).
    `log_categories` - App Service diagnostic categories to stream.
    `app_insights.sampling_percentage` - 0-100.
    `app_insights.disable_ip_masking` - keep client IP addresses unmasked.
  EOT

  validation {
    condition     = var.observability.retention_in_days == -1 || (var.observability.retention_in_days >= 30 && var.observability.retention_in_days <= 730)
    error_message = "observability.retention_in_days must be -1 (unlimited) or between 30 and 730."
  }

  validation {
    condition     = var.observability.app_insights.sampling_percentage >= 0 && var.observability.app_insights.sampling_percentage <= 100
    error_message = "observability.app_insights.sampling_percentage must be between 0 and 100."
  }
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "network" {
  type = object({
    subnet_id                     = optional(string)
    public_network_access_enabled = optional(bool, true)
  })
  default = {}
  description = <<-EOT
    Network placement of the service.

    `subnet_id` - regional virtual network subnet for private egress (VNet
    integration). The subnet must be delegated to `Microsoft.Web/serverFarms`
    and be in the same region as the service.

    `public_network_access_enabled` - set false to stop the app answering on its
    public hostname; combine with private endpoints or a private front door
    (composed outside this module), otherwise the service becomes unreachable.
  EOT
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every taggable resource the module creates."
}
