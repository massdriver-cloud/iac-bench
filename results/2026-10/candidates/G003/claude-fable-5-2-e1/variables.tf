# ---------------------------------------------------------------------------------------------
# Required: what the service is, where it runs, what it runs, how we know it is healthy.
# ---------------------------------------------------------------------------------------------

variable "name" {
  description = "Service name including its environment, e.g. \"orders-api-prod\". Used to name every resource (rg-<name>, asp-<name>, app-<name>-<hash>, ...)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3-40 characters: lowercase letters, digits and single hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region, e.g. \"eastus2\". With the default capacity settings it must be a region where App Service supports availability zones."
  type        = string
}

variable "image" {
  description = <<-EOT
    Fully qualified container image to release, e.g. "myacr.azurecr.io/payments/orders-api:1.4.2" or
    "...orders-api@sha256:<digest>". Changing this value is how you roll out a new version: the module
    starts it in the staging slot, waits for the health endpoint to answer, and swaps it into production.
    A tag (or digest) is mandatory and ":latest" is rejected, because a rollout is triggered by this
    string changing and a mutable tag would make releases invisible and rollbacks impossible.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*(\\.[a-z0-9][a-z0-9-]*)+(:[0-9]+)?/[a-z0-9]+([._/-][a-z0-9]+)*(:[A-Za-z0-9_][A-Za-z0-9._-]{0,127}|@sha256:[a-f0-9]{64})$", var.image))
    error_message = "image must be fully qualified with a registry host and an explicit tag or digest, e.g. \"myacr.azurecr.io/team/app:1.4.2\"."
  }

  validation {
    condition     = !endswith(var.image, ":latest")
    error_message = "image must not use the \":latest\" tag. Pin a version tag or a sha256 digest."
  }
}

variable "health_check_path" {
  description = <<-EOT
    HTTP path of the service's health endpoint, e.g. "/healthz". It must answer 2xx without
    authentication when the instance can serve traffic. There is deliberately no default: this one path
    drives instance health/eviction, the readiness gate before a release is swapped into production,
    and the unhealthy-instance alert, so a guessed value that the app does not serve would silently
    break all three.
  EOT
  type        = string

  validation {
    condition     = can(regex("^/[A-Za-z0-9/_.~-]*$", var.health_check_path))
    error_message = "health_check_path must be a URL path starting with \"/\" and without a query string."
  }
}

# ---------------------------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Existing resource group to deploy into. Leave null (default) and the module creates and owns \"rg-<name>\"."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags added to every resource, on top of the module's own service / managed-by tags."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------------------------
# Container
# ---------------------------------------------------------------------------------------------

variable "container_port" {
  description = "Port the container listens on for HTTP. TLS is terminated by App Service."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer between 1 and 65535."
  }
}

variable "registry" {
  description = <<-EOT
    How the image is pulled.
      acr_id            Resource ID of the Azure Container Registry that hosts `image`. When set, the
                        app pulls with its managed identity (no registry passwords anywhere). When
                        null, the image is pulled anonymously, which only works for public registries.
      grant_pull        Create the AcrPull role assignment for the app's identity on that registry.
                        Set false if your deployment principal cannot assign roles and the grant is
                        made elsewhere (use the identity_principal_id output).
      pull_over_vnet    Pull the image through the VNet integration (needed when the registry is only
                        reachable privately). Requires network.integration_subnet_id.
  EOT
  type = object({
    acr_id         = optional(string)
    grant_pull     = optional(bool, true)
    pull_over_vnet = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.registry.acr_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerRegistry/registries/[A-Za-z0-9]+$", var.registry.acr_id))
    error_message = "registry.acr_id must be a full Azure Container Registry resource ID."
  }
}

variable "app_settings" {
  description = <<-EOT
    Non-secret environment variables for the container. They are part of a release: changing them
    rolls out through the staging slot exactly like a new image. Do not put secrets here (they would
    be stored in plain text in state and in the portal) - use `key_vault` instead.
  EOT
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k in keys(var.app_settings) :
      can(regex("^[A-Za-z_][A-Za-z0-9_.:-]*$", k))
      && !startswith(upper(k), "DOCKER_")
      && !startswith(upper(k), "WEBSITE")
      && !contains(["APPLICATIONINSIGHTS_CONNECTION_STRING", "AZURE_CLIENT_ID"], upper(k))
    ])
    error_message = "app_settings keys must be valid environment variable names and must not use names the module manages (DOCKER_*, WEBSITE*, APPLICATIONINSIGHTS_CONNECTION_STRING, AZURE_CLIENT_ID)."
  }
}

variable "key_vault" {
  description = <<-EOT
    Secrets delivered to the container as environment variables through Key Vault references, so
    secret values never pass through this module or its state.
      id            Resource ID of the Key Vault (must use Azure RBAC authorization for grant_access).
      secrets       Map of environment variable name => secret name in that vault. The latest version
                    is used; App Service picks up rotations within 24h.
      grant_access  Assign "Key Vault Secrets User" on the vault to the app's identity. Set false if
                    the grant is made elsewhere (use the identity_principal_id output).
  EOT
  type = object({
    id           = string
    secrets      = optional(map(string), {})
    grant_access = optional(bool, true)
  })
  default = null

  validation {
    condition     = var.key_vault == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[A-Za-z0-9-]+$", var.key_vault.id))
    error_message = "key_vault.id must be a full Key Vault resource ID."
  }

  validation {
    condition = var.key_vault == null || alltrue([
      for k, v in var.key_vault.secrets :
      can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k)) && can(regex("^[0-9A-Za-z-]{1,127}$", v))
      && !startswith(upper(k), "DOCKER_") && !startswith(upper(k), "WEBSITE")
    ])
    error_message = "key_vault.secrets must map environment variable names (not DOCKER_* / WEBSITE*) to Key Vault secret names (letters, digits and hyphens)."
  }
}

# ---------------------------------------------------------------------------------------------
# Capacity and availability
# ---------------------------------------------------------------------------------------------

variable "capacity" {
  description = <<-EOT
    Size and scaling of the service's dedicated plan. Defaults are the production standard: three
    instances spread over three availability zones, autoscaling to ten.
      sku                       Premium v3 size. Premium v3 is the only tier offered because zone
                                redundancy, autoscale and deployment slots are part of the standard.
      min_instances             Floor for autoscale. Must be >= 2 when zone_redundant.
      max_instances             Ceiling for autoscale. Equal to min_instances = fixed capacity.
      zone_redundant            Spread instances across availability zones. Cannot be changed after
                                creation without replacing the plan. Set false in regions without
                                zones or for throwaway environments.
      cpu_scale_out_percent     Average plan CPU that adds an instance (one is removed again 30 points lower).
      memory_scale_out_percent  Average plan memory that adds an instance (one is removed again 20 points lower).
    For a small non-production footprint use e.g. { sku = "P0v3", min_instances = 1, max_instances = 2, zone_redundant = false }.
  EOT
  type = object({
    sku                      = optional(string, "P1v3")
    min_instances            = optional(number, 3)
    max_instances            = optional(number, 10)
    zone_redundant           = optional(bool, true)
    cpu_scale_out_percent    = optional(number, 70)
    memory_scale_out_percent = optional(number, 80)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3"], var.capacity.sku)
    error_message = "capacity.sku must be a Premium v3 size: P0v3, P1v3, P2v3, P3v3, P1mv3, P2mv3, P3mv3, P4mv3 or P5mv3."
  }

  validation {
    condition     = var.capacity.min_instances >= 1 && var.capacity.max_instances >= var.capacity.min_instances && var.capacity.max_instances <= 30
    error_message = "capacity requires 1 <= min_instances <= max_instances <= 30."
  }

  validation {
    condition     = !var.capacity.zone_redundant || var.capacity.min_instances >= 2
    error_message = "capacity.min_instances must be at least 2 when capacity.zone_redundant is true (a single instance cannot span zones). Raise min_instances or set zone_redundant = false."
  }

  validation {
    condition     = var.capacity.cpu_scale_out_percent >= 50 && var.capacity.cpu_scale_out_percent <= 90 && var.capacity.memory_scale_out_percent >= 50 && var.capacity.memory_scale_out_percent <= 95
    error_message = "capacity.cpu_scale_out_percent must be 50-90 and capacity.memory_scale_out_percent must be 50-95."
  }
}

variable "health_check_eviction_minutes" {
  description = "Minutes an instance may fail the health check before App Service takes it out of rotation (and later replaces it)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10 && floor(var.health_check_eviction_minutes) == var.health_check_eviction_minutes
    error_message = "health_check_eviction_minutes must be an integer between 2 and 10."
  }
}

# ---------------------------------------------------------------------------------------------
# Network exposure
# ---------------------------------------------------------------------------------------------

variable "network" {
  description = <<-EOT
    Inbound exposure and outbound routing. By default the service is reachable from the internet over
    HTTPS only (TLS 1.2+), with no outbound VNet integration.
      public_access_enabled    false makes the app reachable only through the private endpoint.
      allowed_cidrs            IPv4 CIDRs allowed to call the public endpoint. If this or
      allowed_service_tags     allowed_service_tags (e.g. "AzureFrontDoor.Backend") is non-empty,
                               everything else is denied. Applies to the deployment (SCM) site too.
      integration_subnet_id    Subnet (delegated to Microsoft.Web/serverFarms) for outbound traffic.
                               When set, all outbound traffic is routed through the VNet.
      private_endpoint         Create a private endpoint for the app in subnet_id and register it in
                               the given privatelink.azurewebsites.net private DNS zone(s).
  EOT
  type = object({
    public_access_enabled = optional(bool, true)
    allowed_cidrs         = optional(list(string), [])
    allowed_service_tags  = optional(list(string), [])
    integration_subnet_id = optional(string)
    private_endpoint = optional(object({
      subnet_id            = string
      private_dns_zone_ids = optional(list(string), [])
    }))
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for c in var.network.allowed_cidrs : can(cidrhost(c, 0)) && !strcontains(c, ":")])
    error_message = "network.allowed_cidrs must be valid IPv4 CIDR blocks, e.g. \"203.0.113.0/24\"."
  }

  validation {
    condition     = var.network.public_access_enabled || var.network.private_endpoint != null
    error_message = "network.public_access_enabled = false leaves the app unreachable unless network.private_endpoint is also set."
  }

  validation {
    condition     = length(var.network.allowed_cidrs) + length(var.network.allowed_service_tags) <= 400
    error_message = "At most 400 access rules (allowed_cidrs + allowed_service_tags) are supported."
  }
}

# ---------------------------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------------------------

variable "observability" {
  description = <<-EOT
    Where telemetry goes. Platform logs (HTTP access, container stdout/stderr, platform, audit) and
    metrics are always shipped to Log Analytics, and a workspace-based Application Insights component
    is always created with its connection string injected as APPLICATIONINSIGHTS_CONNECTION_STRING.
      log_analytics_workspace_id  Existing (e.g. central SRE) workspace. Null creates "log-<name>".
      log_retention_days          Retention of the workspace this module creates (ignored otherwise).
  EOT
  type = object({
    log_analytics_workspace_id = optional(string)
    log_retention_days         = optional(number, 30)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.observability.log_retention_days >= 30 && var.observability.log_retention_days <= 730
    error_message = "observability.log_retention_days must be between 30 and 730."
  }
}

variable "alerts" {
  description = <<-EOT
    Standard alert set: 5xx responses, slow responses, unhealthy instances, and plan CPU / memory
    saturation (i.e. autoscale has run out of road).
      enabled                 Create the alerts.
      action_group_ids        Action groups to notify. IMPORTANT: with the default empty list the
                              alerts fire and show up in Azure Monitor but page nobody.
      http_5xx_count          5xx responses within 5 minutes that trigger the error alert.
      response_time_seconds   Average response time over 15 minutes that triggers the latency alert.
      saturation_percent      Average plan CPU or memory over 15 minutes that triggers the saturation alert.
  EOT
  type = object({
    enabled               = optional(bool, true)
    action_group_ids      = optional(list(string), [])
    http_5xx_count        = optional(number, 10)
    response_time_seconds = optional(number, 2)
    saturation_percent    = optional(number, 90)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.alerts.http_5xx_count >= 0 && var.alerts.response_time_seconds > 0 && var.alerts.saturation_percent > 0 && var.alerts.saturation_percent <= 100
    error_message = "alerts thresholds must be: http_5xx_count >= 0, response_time_seconds > 0, saturation_percent in (0, 100]."
  }
}
