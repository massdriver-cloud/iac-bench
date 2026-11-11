###############################################################################
# Identity of the service
###############################################################################

variable "name" {
  description = "Short name of the service (e.g. \"orders-api\"). Used to derive every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.name))
    error_message = "name must be 3-24 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment short name (e.g. \"dev\", \"staging\", \"prod\"). Part of every resource name and tag set."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.environment))
    error_message = "environment must be 2-8 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region for all resources (e.g. \"westeurope\"). Must support availability zones unless capacity.zone_redundant is false."
  type        = string
}

variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into. When null the module creates \"rg-<name>-<environment>\"."
  type        = string
  default     = null
}

variable "app_name" {
  description = "Override for the web app name (must be globally unique, it becomes <app_name>.azurewebsites.net). When null the module uses \"app-<name>-<environment>-<6 char hash>\", where the hash is derived from the subscription and resource group so it is stable across runs."
  type        = string
  default     = null

  validation {
    condition     = var.app_name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$", var.app_name))
    error_message = "app_name must be 2-60 characters of letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "tags" {
  description = "Extra tags applied to every resource, merged over the module's standard tags."
  type        = map(string)
  default     = {}
}

###############################################################################
# Workload: container image and configuration
###############################################################################

variable "image" {
  description = <<-EOT
    Container image to run.
      registry   - registry host name without scheme, e.g. "myacr.azurecr.io" or "mcr.microsoft.com".
      repository - repository path, e.g. "payments/orders-api".
      tag        - immutable image tag. "latest" is rejected so that every rollout is a deliberate, reproducible change.

    Rollout behaviour: after the first apply, changing this value updates the
    STAGING slot only. Production keeps serving the current image until the
    slots are swapped (see the "rollout" output). See README.md.
  EOT
  type = object({
    registry   = string
    repository = string
    tag        = string
  })

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]*(:[0-9]+)?$", var.image.registry))
    error_message = "image.registry must be a bare host name (optionally with a port), without \"https://\" or a path."
  }

  validation {
    condition     = can(regex("^[a-z0-9]+([._/-][a-z0-9]+)*$", var.image.repository))
    error_message = "image.repository must be a lowercase repository path such as \"team/service\", without a tag."
  }

  validation {
    condition     = can(regex("^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$", var.image.tag)) && lower(var.image.tag) != "latest"
    error_message = "image.tag must be a valid, explicit image tag. \"latest\" is not allowed."
  }
}

variable "container_registry_id" {
  description = "Resource ID of the Azure Container Registry that hosts the image. When set, the app's managed identity is granted AcrPull on it. Leave null for public registries or when the role is assigned elsewhere. Images in *.azurecr.io registries are always pulled with the managed identity, never with admin credentials."
  type        = string
  default     = null
}

variable "container_port" {
  description = "TCP port the container listens on for HTTP."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "app_settings" {
  description = "Non-secret environment variables for the container. Do NOT put secrets here (they end up in state and in the portal in clear text); use key_vault_secrets instead. Changing settings restarts the production app."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k in keys(var.app_settings) :
      !contains(["WEBSITES_PORT", "WEBSITES_ENABLE_APP_SERVICE_STORAGE", "WEBSITE_SWAP_WARMUP_PING_PATH", "WEBSITE_SWAP_WARMUP_PING_STATUSES", "APPLICATIONINSIGHTS_CONNECTION_STRING"], k)
      && !startswith(k, "DOCKER_")
    ])
    error_message = "app_settings must not contain settings the module manages: WEBSITES_PORT, WEBSITES_ENABLE_APP_SERVICE_STORAGE, WEBSITE_SWAP_WARMUP_PING_*, APPLICATIONINSIGHTS_CONNECTION_STRING or DOCKER_*."
  }
}

variable "key_vault_secrets" {
  description = "Secrets exposed to the container as environment variables, as a map of ENV_VAR_NAME => Key Vault secret URI (e.g. \"https://kv-x.vault.azure.net/secrets/db-password\"). The platform resolves them at runtime with the app's managed identity; secret values never pass through OpenTofu."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for uri in values(var.key_vault_secrets) : can(regex("^https://[^/]+/secrets/[^/]+(/[0-9a-fA-F]+)?/?$", uri))])
    error_message = "Every key_vault_secrets value must be a Key Vault secret URI of the form https://<vault>/secrets/<name>[/<version>]."
  }

  validation {
    condition = alltrue([
      for k in keys(var.key_vault_secrets) :
      !contains(["WEBSITES_PORT", "WEBSITES_ENABLE_APP_SERVICE_STORAGE", "WEBSITE_SWAP_WARMUP_PING_PATH", "WEBSITE_SWAP_WARMUP_PING_STATUSES", "APPLICATIONINSIGHTS_CONNECTION_STRING"], k)
      && !startswith(k, "DOCKER_")
    ])
    error_message = "key_vault_secrets must not use setting names the module manages."
  }
}

variable "key_vault_ids" {
  description = "Resource IDs of (RBAC-mode) Key Vaults referenced by key_vault_secrets. The app's managed identity is granted \"Key Vault Secrets User\" on each. Leave empty if access is granted elsewhere."
  type        = list(string)
  default     = []
}

variable "sticky_app_setting_names" {
  description = "Names of app settings that stay with their slot during a swap instead of travelling with the release."
  type        = list(string)
  default     = []
}

###############################################################################
# Capacity & availability
###############################################################################

variable "capacity" {
  description = <<-EOT
    Compute capacity and availability of the App Service plan.
      sku                      - Premium v3 size: P0v3..P3v3 or P1mv3..P5mv3.
      min_instances            - instances always running.
      max_instances            - autoscale ceiling. Equal to min_instances = fixed capacity, no autoscale rules.
      zone_redundant           - spread instances across availability zones (needs min_instances >= 2 and a region
                                 with zones). Changing this on an existing plan replaces the plan.
      scale_out_cpu_percent    - add an instance when average plan CPU stays above this for 10 minutes.
      scale_in_cpu_percent     - remove an instance when average plan CPU stays below this for 15 minutes.
      scale_out_memory_percent - add an instance when average plan memory stays above this for 10 minutes.
    The instance count is owned by the autoscale setting, not by the plan resource, so applies never fight autoscale.
  EOT
  type = object({
    sku                      = optional(string, "P1v3")
    min_instances            = optional(number, 2)
    max_instances            = optional(number, 6)
    zone_redundant           = optional(bool, true)
    scale_out_cpu_percent    = optional(number, 70)
    scale_in_cpu_percent     = optional(number, 30)
    scale_out_memory_percent = optional(number, 80)
  })
  default = {}

  validation {
    condition     = can(regex("^P([0-3]v3|[1-5]mv3)$", var.capacity.sku))
    error_message = "capacity.sku must be a Premium v3 SKU (P0v3, P1v3, P2v3, P3v3, P1mv3..P5mv3): the module relies on deployment slots, autoscale and zone redundancy."
  }

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances && var.capacity.max_instances <= 30
    error_message = "capacity requires 1 <= min_instances <= max_instances <= 30."
  }

  validation {
    condition     = !var.capacity.zone_redundant || var.capacity.min_instances >= 2
    error_message = "capacity.zone_redundant requires min_instances >= 2. For a single-instance (non-HA) deployment set zone_redundant = false explicitly."
  }

  validation {
    condition     = var.capacity.scale_in_cpu_percent > 0 && var.capacity.scale_in_cpu_percent < var.capacity.scale_out_cpu_percent && var.capacity.scale_out_cpu_percent <= 100 && var.capacity.scale_out_memory_percent > 0 && var.capacity.scale_out_memory_percent <= 100
    error_message = "capacity thresholds must satisfy 0 < scale_in_cpu_percent < scale_out_cpu_percent <= 100 and 0 < scale_out_memory_percent <= 100."
  }
}

###############################################################################
# Health
###############################################################################

variable "health_check_path" {
  description = "HTTP path the platform probes on every instance once a minute. Must return 2xx when the instance can serve traffic. Unhealthy instances are taken out of rotation and eventually replaced; the same path gates slot swaps."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with \"/\"."
  }
}

variable "health_check_eviction_minutes" {
  description = "Minutes of consecutive failed probes before an instance is removed from the load balancer (2-10)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10 && floor(var.health_check_eviction_minutes) == var.health_check_eviction_minutes
    error_message = "health_check_eviction_minutes must be an integer between 2 and 10."
  }
}

###############################################################################
# Network exposure
###############################################################################

variable "ingress" {
  description = <<-EOT
    Who can reach the app (production and staging slot alike; the Kudu/SCM site follows the same rules).
      mode - "private"    (default) public endpoint disabled; reachable only through a private endpoint.
             "restricted" public endpoint enabled, default-deny, only the allow-lists below get through.
             "public"     public endpoint open to the internet.
      allowed_cidrs        - IPv4/IPv6 CIDR ranges                                  (restricted mode only)
      allowed_service_tags - Azure service tags, e.g. "ApiManagement"               (restricted mode only)
      allowed_subnet_ids   - subnets with the Microsoft.Web service endpoint        (restricted mode only)
      front_door_ids       - Front Door profile IDs (X-Azure-FDID GUIDs); allows only AzureFrontDoor.Backend
                             traffic carrying one of these IDs                      (restricted mode only)
      private_endpoint_subnet_id - subnet in which to create private endpoints for the app and its staging slot
                                   (any mode). When null in "private" mode, the app is unreachable until a
                                   private endpoint is attached by other means.
      private_dns_zone_ids       - privatelink.azurewebsites.net zone(s) to register the private endpoints in.
  EOT
  type = object({
    mode                       = optional(string, "private")
    allowed_cidrs              = optional(list(string), [])
    allowed_service_tags       = optional(list(string), [])
    allowed_subnet_ids         = optional(list(string), [])
    front_door_ids             = optional(list(string), [])
    private_endpoint_subnet_id = optional(string)
    private_dns_zone_ids       = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = contains(["private", "restricted", "public"], var.ingress.mode)
    error_message = "ingress.mode must be \"private\", \"restricted\" or \"public\"."
  }

  validation {
    condition = (
      var.ingress.mode == "restricted"
      ? length(var.ingress.allowed_cidrs) + length(var.ingress.allowed_service_tags) + length(var.ingress.allowed_subnet_ids) + length(var.ingress.front_door_ids) > 0
      : length(var.ingress.allowed_cidrs) + length(var.ingress.allowed_service_tags) + length(var.ingress.allowed_subnet_ids) + length(var.ingress.front_door_ids) == 0
    )
    error_message = "Allow-lists (allowed_cidrs, allowed_service_tags, allowed_subnet_ids, front_door_ids) are required in \"restricted\" mode and must be empty in every other mode, where they would have no effect."
  }

  validation {
    condition     = alltrue([for c in var.ingress.allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "ingress.allowed_cidrs entries must be valid CIDR ranges, e.g. \"203.0.113.0/24\" or \"198.51.100.7/32\"."
  }

  validation {
    condition     = !contains(var.ingress.allowed_cidrs, "0.0.0.0/0") && !contains(var.ingress.allowed_cidrs, "::/0")
    error_message = "Allow-listing 0.0.0.0/0 or ::/0 defeats \"restricted\" mode. Use mode = \"public\" if the app is meant to be open to the internet."
  }

  validation {
    condition     = length(var.ingress.front_door_ids) <= 8
    error_message = "At most 8 front_door_ids are supported by a single access restriction rule."
  }

  validation {
    condition     = length(var.ingress.private_dns_zone_ids) == 0 || var.ingress.private_endpoint_subnet_id != null
    error_message = "ingress.private_dns_zone_ids only has an effect together with private_endpoint_subnet_id."
  }
}

variable "vnet_integration_subnet_id" {
  description = "Subnet (delegated to Microsoft.Web/serverFarms) for outbound VNet integration. When set, all outbound traffic from the app is routed through the VNet. When null the app egresses directly to the internet."
  type        = string
  default     = null
}

###############################################################################
# Observability
###############################################################################

variable "log_analytics_workspace_id" {
  description = "Resource ID of an existing Log Analytics workspace to receive logs and back Application Insights. When null the module creates a workspace for this service."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention of the module-created Log Analytics workspace, in days. Ignored when log_analytics_workspace_id is set."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "application_insights_enabled" {
  description = "Create a workspace-based Application Insights component and inject APPLICATIONINSIGHTS_CONNECTION_STRING into the container, for apps instrumented with the Azure Monitor / OpenTelemetry SDKs."
  type        = bool
  default     = true
}

variable "alerts" {
  description = <<-EOT
    Standard metric alerts for the service.
      enabled               - create the alert rules.
      action_group_ids      - Azure Monitor action groups to notify. With the default (empty) the rules still
                              evaluate and show up in Azure Monitor, but nobody is paged.
      http_5xx_count        - fire (sev 1) when more than this many HTTP 5xx responses occur within 5 minutes.
      min_healthy_percent   - fire (sev 1) when the share of instances passing the health check averages below
                              this over 5 minutes.
      response_time_seconds - fire (sev 2) when average response time exceeds this over 15 minutes.
      plan_cpu_percent      - fire (sev 2) when average plan CPU exceeds this over 15 minutes (autoscale exhausted).
      plan_memory_percent   - fire (sev 2) when average plan memory exceeds this over 15 minutes.
  EOT
  type = object({
    enabled               = optional(bool, true)
    action_group_ids      = optional(list(string), [])
    http_5xx_count        = optional(number, 10)
    min_healthy_percent   = optional(number, 90)
    response_time_seconds = optional(number, 3)
    plan_cpu_percent      = optional(number, 90)
    plan_memory_percent   = optional(number, 90)
  })
  default = {}

  validation {
    condition     = var.alerts.min_healthy_percent > 0 && var.alerts.min_healthy_percent <= 100 && var.alerts.plan_cpu_percent > 0 && var.alerts.plan_cpu_percent <= 100 && var.alerts.plan_memory_percent > 0 && var.alerts.plan_memory_percent <= 100
    error_message = "alerts percentages must be within (0, 100]."
  }

  validation {
    condition     = var.alerts.http_5xx_count >= 0 && var.alerts.response_time_seconds > 0
    error_message = "alerts.http_5xx_count must be >= 0 and alerts.response_time_seconds must be > 0."
  }
}
