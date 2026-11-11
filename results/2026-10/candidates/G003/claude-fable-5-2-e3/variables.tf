###############################################################################
# Identity of the service
###############################################################################

variable "name" {
  description = "Short name of the service, e.g. \"orders-api\". Used in every resource name and in the public hostname."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 2-32 characters of lowercase letters, digits and single hyphens, start with a letter and end with a letter or digit."
  }
}

variable "environment" {
  description = "Environment this instance of the service runs in, e.g. \"dev\", \"staging\", \"prod\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters or digits, starting with a letter."
  }
}

variable "location" {
  description = "Azure region for all resources, e.g. \"swedencentral\". Must support availability zones for App Service unless zone_redundant is set to false."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be the short region name (lowercase, no spaces), e.g. \"westeurope\"."
  }
}

variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into. Leave null (default) to have the module create a dedicated resource group \"rg-<name>-<environment>\"."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags applied to every resource, merged over the module's standard tags (service, environment, managed-by)."
  type        = map(string)
  default     = {}
}

###############################################################################
# What runs
###############################################################################

variable "image" {
  description = <<-EOT
    Full reference of the container image served by the production slot, as
    "<registry host>/<repository>:<tag>", e.g. "contoso.azurecr.io/payments/orders-api:1.4.2".
    The tag must be an immutable version: "latest" is rejected so that every
    rollout (and rollback) is an explicit, reviewable change.
    Images on Azure Container Registry are pulled with the service's managed
    identity; any other registry is pulled anonymously (public images only).
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}(:[0-9]+)?/[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image))
    error_message = "image must look like \"<registry host>/<repository>:<tag>\", e.g. \"contoso.azurecr.io/team/api:1.4.2\". The registry host and an explicit tag are required."
  }

  validation {
    condition     = !endswith(var.image, ":latest")
    error_message = "image must be pinned to an immutable version tag; \"latest\" is not allowed."
  }
}

variable "container_port" {
  description = "TCP port the container listens on for HTTP. TLS is terminated by the platform; the container speaks plain HTTP."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "container_registry_id" {
  description = "Resource ID of the Azure Container Registry that hosts the image. When set, the module grants the service identity AcrPull on it. Leave null for public registries, or if AcrPull is granted elsewhere (use the identity_principal_id output)."
  type        = string
  default     = null

  validation {
    condition     = var.container_registry_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerRegistry/registries/[^/]+$", var.container_registry_id))
    error_message = "container_registry_id must be the full resource ID of an Azure Container Registry."
  }
}

variable "app_settings" {
  description = "Non-secret environment variables for the container. Do not put secrets here (they end up in state and plan output) - use key_vault_secrets instead."
  type        = map(string)
  default     = {}

  validation {
    condition = length(setintersection(keys(var.app_settings), [
      "WEBSITES_PORT",
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE",
      "WEBSITE_SWAP_WARMUP_PING_PATH",
      "WEBSITE_SWAP_WARMUP_PING_STATUSES",
      "APPLICATIONINSIGHTS_CONNECTION_STRING",
      "AZURE_CLIENT_ID",
      "DOCKER_REGISTRY_SERVER_URL",
      "DOCKER_REGISTRY_SERVER_USERNAME",
      "DOCKER_REGISTRY_SERVER_PASSWORD",
    ])) == 0
    error_message = "app_settings must not set WEBSITES_PORT, WEBSITES_ENABLE_APP_SERVICE_STORAGE, WEBSITE_SWAP_WARMUP_PING_*, APPLICATIONINSIGHTS_CONNECTION_STRING, AZURE_CLIENT_ID or DOCKER_REGISTRY_SERVER_*: the module manages these."
  }
}

variable "key_vault_secrets" {
  description = "Secret environment variables, as a map of variable name => Key Vault secret URI (e.g. \"https://kv-payments.vault.azure.net/secrets/db-password\"). They are injected as Key Vault references resolved with the service's managed identity, so secret values never pass through OpenTofu. Omit the version from the URI to pick up rotations automatically."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for uri in values(var.key_vault_secrets) : can(regex("^https://[a-zA-Z0-9-]+\\.[a-z0-9.-]+/secrets/[a-zA-Z0-9-]+(/[a-f0-9]*)?$", uri))])
    error_message = "Every value in key_vault_secrets must be a Key Vault secret URI such as \"https://<vault>.vault.azure.net/secrets/<name>\"."
  }
}

variable "key_vault_ids" {
  description = "Resource IDs of the Key Vaults (RBAC permission model) referenced by key_vault_secrets. The module grants the service identity \"Key Vault Secrets User\" on each. Leave empty if access is granted elsewhere."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.key_vault_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", id))])
    error_message = "Every entry in key_vault_ids must be the full resource ID of a Key Vault."
  }
}

###############################################################################
# Capacity and availability
###############################################################################

variable "sku_name" {
  description = "Instance size of the dedicated App Service plan. Only Premium v3 is offered because the module's guarantees (zone redundancy, autoscale, deployment slots, VNet integration, private endpoints) all depend on it. P0v3 = 1 vCPU/4 GiB, P1v3 = 2 vCPU/8 GiB, P2v3 = 4 vCPU/16 GiB, P3v3 = 8 vCPU/32 GiB; the \"m\" sizes are memory-optimised."
  type        = string
  default     = "P1v3"

  validation {
    condition     = contains(["P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3"], var.sku_name)
    error_message = "sku_name must be a Premium v3 size: P0v3, P1v3, P2v3, P3v3, P1mv3, P2mv3, P3mv3, P4mv3 or P5mv3."
  }
}

variable "min_instances" {
  description = "Minimum (and initial) number of instances. Keep at 2 or more for any service that must survive an instance or zone failure."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 30 && floor(var.min_instances) == var.min_instances
    error_message = "min_instances must be an integer between 1 and 30."
  }
}

variable "max_instances" {
  description = "Maximum number of instances autoscale may run. Set equal to min_instances for a fixed-size service."
  type        = number
  default     = 4

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30 && floor(var.max_instances) == var.max_instances
    error_message = "max_instances must be an integer between 1 and 30."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires min_instances >= 2 and a region with availability zones. Changing this after creation may require replacing the plan."
  type        = bool
  default     = true
}

variable "scale_out_cpu_percent" {
  description = "Add an instance when average CPU across the plan stays above this percentage for 5 minutes."
  type        = number
  default     = 70

  validation {
    condition     = var.scale_out_cpu_percent >= 20 && var.scale_out_cpu_percent <= 95
    error_message = "scale_out_cpu_percent must be between 20 and 95."
  }
}

variable "scale_in_cpu_percent" {
  description = "Remove an instance when average CPU across the plan stays below this percentage for 10 minutes. Must leave a clear gap below scale_out_cpu_percent to avoid flapping."
  type        = number
  default     = 35

  validation {
    condition     = var.scale_in_cpu_percent >= 5 && var.scale_in_cpu_percent <= 80
    error_message = "scale_in_cpu_percent must be between 5 and 80."
  }
}

###############################################################################
# Health
###############################################################################

variable "health_check_path" {
  description = "HTTP path the platform probes on every instance once a minute, e.g. \"/healthz\". It must return 2xx when the instance can serve traffic. Unhealthy instances are taken out of rotation and eventually replaced; the same path is used to warm up a slot before a swap."
  type        = string

  validation {
    condition     = can(regex("^/[^\\s?#]*$", var.health_check_path))
    error_message = "health_check_path must be an absolute path starting with \"/\" and without query string, e.g. \"/healthz\"."
  }
}

variable "health_check_eviction_minutes" {
  description = "Minutes of consecutive failed health probes before an instance is removed from the load balancer."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10 && floor(var.health_check_eviction_minutes) == var.health_check_eviction_minutes
    error_message = "health_check_eviction_minutes must be an integer between 2 and 10."
  }
}

###############################################################################
# Rollouts
###############################################################################

variable "staging_slot_enabled" {
  description = "Create a \"staging\" deployment slot for blue/green rollouts: deploy a new image to staging, verify it, then swap it into production with zero downtime."
  type        = bool
  default     = true
}

variable "staging_image" {
  description = "Image reference for the staging slot, in the same format as image. Null (default) keeps staging on the production image. Set it to the release candidate to start a rollout."
  type        = string
  default     = null

  validation {
    condition     = var.staging_image == null || can(regex("^[a-z0-9][a-z0-9.-]*\\.[a-z]{2,}(:[0-9]+)?/[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.staging_image))
    error_message = "staging_image must look like \"<registry host>/<repository>:<tag>\"."
  }

  validation {
    condition     = var.staging_image == null || !endswith(coalesce(var.staging_image, "-"), ":latest")
    error_message = "staging_image must be pinned to an immutable version tag; \"latest\" is not allowed."
  }
}

variable "staging_app_settings" {
  description = "Environment variables that differ on the staging slot (overrides on top of app_settings). These names are marked slot-sticky on both slots, so they stay put when the slots are swapped. Declare the production value in app_settings as well if production needs one."
  type        = map(string)
  default     = {}
}

###############################################################################
# Traffic and networking
###############################################################################

variable "public_network_access_enabled" {
  description = "Whether the service is reachable on its public endpoint. Set to false for services that are only reached through a private endpoint."
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "IPv4 CIDR ranges allowed to call the public endpoint. If this, allowed_service_tags and front_door_id are all empty, the public endpoint accepts traffic from anywhere; as soon as one is set, everything else is denied."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.allowed_ip_ranges : can(cidrhost(cidr, 0))])
    error_message = "Every entry in allowed_ip_ranges must be a valid CIDR range, e.g. \"203.0.113.0/24\"."
  }
}

variable "allowed_service_tags" {
  description = "Azure service tags allowed to call the public endpoint, e.g. [\"ApiManagement\"]. For Azure Front Door use front_door_id instead, which also pins the caller to your own profile."
  type        = list(string)
  default     = []
}

variable "front_door_id" {
  description = "Front Door ID (the profile's resource GUID, sent as X-Azure-FDID). When set, traffic from that Front Door profile is allowed and other Front Door tenants are rejected."
  type        = string
  default     = null

  validation {
    condition     = var.front_door_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.front_door_id))
    error_message = "front_door_id must be a GUID."
  }
}

variable "integration_subnet_id" {
  description = "Subnet (delegated to Microsoft.Web/serverFarms) for outbound VNet integration. When set, all outbound traffic, including image pulls, is routed through the virtual network."
  type        = string
  default     = null
}

variable "private_endpoint_subnet_id" {
  description = "Subnet in which to create private endpoints for the service (and its staging slot). Null (default) creates none."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "IDs of the privatelink.azurewebsites.net private DNS zone(s) to register the private endpoints in. Leave empty if DNS records are managed centrally (e.g. by Azure Policy)."
  type        = list(string)
  default     = []
}

variable "session_affinity_enabled" {
  description = "Pin clients to an instance with an affinity cookie. Off by default: stateless APIs load-balance and scale better without it."
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to call the API (platform-level CORS), e.g. [\"https://app.contoso.com\"]. Leave empty if the API is not called from browsers or handles CORS itself."
  type        = list(string)
  default     = []
}

###############################################################################
# Observability
###############################################################################

variable "log_analytics_workspace_id" {
  description = "Resource ID of an existing Log Analytics workspace (typically the SRE team's central one) to receive logs and back Application Insights. Null (default) creates a dedicated workspace for the service."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention of the dedicated Log Analytics workspace. Ignored when log_analytics_workspace_id is set."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "log_retention_days must be an integer between 30 and 730."
  }
}

variable "alerts_enabled" {
  description = "Create the standard alert rules (5xx errors, latency, failed health checks, plan CPU and memory saturation)."
  type        = bool
  default     = true
}

variable "alert_action_group_ids" {
  description = "Resource IDs of existing Azure Monitor action groups (PagerDuty, Opsgenie, Teams, ...) to notify when an alert fires or resolves."
  type        = list(string)
  default     = []
}

variable "alert_email_addresses" {
  description = "Email addresses to notify when an alert fires. When non-empty the module creates an action group for them, in addition to alert_action_group_ids. With neither set, alerts are still evaluated and visible in Azure Monitor but nobody is notified."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.alert_email_addresses : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email))])
    error_message = "Every entry in alert_email_addresses must be an email address."
  }
}

variable "alert_thresholds" {
  description = <<-EOT
    Thresholds for the standard alerts:
      http_5xx_count        - HTTP 5xx responses within 5 minutes
      response_time_seconds - average response time over 5 minutes
      health_check_percent  - average share of healthy instances over 5 minutes (alert when below)
      cpu_percent           - average plan CPU over 15 minutes
      memory_percent        - average plan memory over 15 minutes
  EOT
  type = object({
    http_5xx_count        = optional(number, 10)
    response_time_seconds = optional(number, 2)
    health_check_percent  = optional(number, 80)
    cpu_percent           = optional(number, 90)
    memory_percent        = optional(number, 90)
  })
  default = {}
}
