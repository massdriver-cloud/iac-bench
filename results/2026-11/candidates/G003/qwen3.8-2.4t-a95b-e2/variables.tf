# ---------------------------------------------------------------------------
# Identity of the service
# ---------------------------------------------------------------------------

variable "service_name" {
  type        = string
  description = <<-EOT
    Name of the service being onboarded (e.g. "orders-api"). Becomes the web
    app name and seeds the names of all supporting resources. Must be unique
    across Azure (it is part of the app's public hostname), 2-60 characters,
    lowercase letters, digits and hyphens, not starting/ending with a hyphen.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,58}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 2-60 chars of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment name used for tagging and reporting (e.g. prod, staging, dev)."
  default     = "prod"
}

variable "location" {
  type        = string
  description = "Azure region for all resources."
  default     = "westeurope"
}

variable "resource_group_name" {
  type        = string
  description = "Optional explicit resource group name. Defaults to \"<service_name>-rg\"."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged on top of the module's standard tags (service, environment, managed-by)."
  default     = {}
}

# ---------------------------------------------------------------------------
# The container the service runs
# ---------------------------------------------------------------------------

variable "container_image" {
  type        = string
  description = <<-EOT
    Container image to run, as "repository:tag" relative to the registry URL
    (e.g. "myteam/orders-api:1.4.2"). Changing the tag is the normal way to
    roll out a new version.
  EOT
}

variable "container_registry_url" {
  type        = string
  description = "Base URL of the container registry the image is pulled from."
  default     = "https://mcr.microsoft.com"
}

variable "container_registry_username" {
  type        = string
  description = "Username for the container registry, if it requires credentials. Leave null for anonymous registries or managed-identity pulls."
  default     = null
  sensitive   = true
}

variable "container_registry_password" {
  type        = string
  description = "Password/token for the container registry, if it requires credentials."
  default     = null
  sensitive   = true
}

variable "pull_with_managed_identity" {
  type        = bool
  description = <<-EOT
    If true, App Service pulls images using the app's system-assigned managed
    identity instead of stored credentials. Requires container_registry_resource_id
    so the module can grant AcrPull.
  EOT
  default     = false
}

variable "container_registry_resource_id" {
  type        = string
  description = "Resource ID of the Azure Container Registry to grant AcrPull on (used when pull_with_managed_identity is true)."
  default     = null
}

variable "container_port" {
  type        = number
  description = "Port the container listens on. Only needed when the image does not declare it via EXPOSE; leave null to let the platform auto-detect."
  default     = null

  validation {
    condition     = var.container_port == null || (var.container_port >= 1 && var.container_port <= 65535)
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "app_command_line" {
  type        = string
  description = "Optional override of the container's startup command."
  default     = null
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

variable "sku_name" {
  type        = string
  description = <<-EOT
    App Service Plan SKU. The module's standard for production HTTP APIs is
    P1v3 (Premium v3): autoscale-capable, zone-redundancy-capable, fast
    containers. B/S SKUs also work if a team needs a cheaper tier.
  EOT
  default     = "P1v3"

  validation {
    condition     = can(regex("^[A-Z]{1,3}[0-9]{1,2}(v[0-9])?$", var.sku_name))
    error_message = "sku_name must look like an App Service SKU, e.g. B1, S2, P1v3, P2mv3."
  }
}

variable "worker_count" {
  type        = number
  description = <<-EOT
    Number of plan workers (instances). Used as the baseline instance count;
    when autoscaling is enabled the autoscale profile controls the actual
    count, starting from autoscale_default_instances.
  EOT
  default     = 2

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

variable "zone_balancing_enabled" {
  type        = bool
  description = <<-EOT
    Spread workers across availability zones (requires a zone-capable SKU such
    as Premium v3 and at least 3 instances at steady state). Recommended for
    production in regions with zones.
  EOT
  default     = false
}

variable "autoscale_enabled" {
  type        = bool
  description = "Enable CPU-based autoscaling of the App Service Plan."
  default     = true
}

variable "autoscale_min_instances" {
  type        = number
  description = "Floor for autoscaling. Two is the module default so a single bad deploy or node failure never takes the service fully offline."
  default     = 2

  validation {
    condition     = var.autoscale_min_instances >= 1
    error_message = "autoscale_min_instances must be at least 1."
  }
}

variable "autoscale_max_instances" {
  type        = number
  description = "Ceiling for autoscaling; the blast-radius cap for runaway traffic or scale-out bugs."
  default     = 10
}

variable "autoscale_default_instances" {
  type        = number
  description = "Instance count autoscaling starts from and returns to."
  default     = 2
}

variable "autoscale_cpu_scale_out_threshold" {
  type        = number
  description = "Average CPU percentage over 5 minutes that triggers scaling out by one worker."
  default     = 75

  validation {
    condition     = var.autoscale_cpu_scale_out_threshold > 0 && var.autoscale_cpu_scale_out_threshold <= 100
    error_message = "autoscale_cpu_scale_out_threshold must be in (0, 100]."
  }
}

variable "autoscale_cpu_scale_in_threshold" {
  type        = number
  description = "Average CPU percentage over 5 minutes that triggers scaling in by one worker."
  default     = 30

  validation {
    condition     = var.autoscale_cpu_scale_in_threshold >= 0 && var.autoscale_cpu_scale_in_threshold < 100
    error_message = "autoscale_cpu_scale_in_threshold must be in [0, 100)."
  }
}

# ---------------------------------------------------------------------------
# Availability & traffic
# ---------------------------------------------------------------------------

variable "always_on" {
  type        = bool
  description = "Keep the app warm at all times instead of unloading it when idle. Standard for production HTTP APIs."
  default     = true
}

variable "http2_enabled" {
  type        = bool
  description = "Enable HTTP/2 on the public endpoint."
  default     = true
}

variable "minimum_tls_version" {
  type        = string
  description = "Minimum TLS version accepted on the public endpoint."
  default     = "1.2"

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.minimum_tls_version)
    error_message = "minimum_tls_version must be one of 1.0, 1.1, 1.2, 1.3."
  }
}

variable "ftps_state" {
  type        = string
  description = "FTPS policy for the app. FtpsOnly is the hardened default; containers have no need for plain FTP."
  default     = "FtpsOnly"

  validation {
    condition     = contains(["AllAllowed", "FtpsOnly", "Disabled"], var.ftps_state)
    error_message = "ftps_state must be one of AllAllowed, FtpsOnly, Disabled."
  }
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Whether the app is reachable from the public internet. Set false to serve it only via private endpoints/VNets."
  default     = true
}

variable "allowed_inbound_ip_cidrs" {
  type        = list(string)
  description = <<-EOT
    Optional allow-list of inbound CIDRs. When non-empty, only these ranges can
    reach the app (access rules are applied in App Service, everything else is
    denied). Leave empty to allow the internet.
  EOT
  default     = []
}

variable "vnet_integration_subnet_id" {
  type        = string
  description = <<-EOT
    Optional subnet resource ID for regional VNet integration (egress into the
    VNet, e.g. to reach private databases). Route-all is enabled automatically.
  EOT
  default     = null
}

# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

variable "health_check_path" {
  type        = string
  description = <<-EOT
    Path App Service pings to decide whether an instance is healthy. Unhealthy
    instances are drained from rotation and eventually replaced. This is the
    contract the service must implement (return 200-299); "/" is acceptable if
    the app has no dedicated endpoint.
  EOT
  default     = "/healthz"

  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "health_check_path must start with a leading slash."
  }
}

variable "health_check_max_ping_failures" {
  type        = number
  description = "Number of consecutive failed health pings before an instance is drained from rotation (2-10)."
  default     = 4

  validation {
    condition     = var.health_check_max_ping_failures >= 2 && var.health_check_max_ping_failures <= 10
    error_message = "health_check_max_ping_failures must be between 2 and 10."
  }
}

variable "health_check_eviction_time_in_min" {
  type        = number
  description = <<-EOT
    Minutes an instance may stay unhealthy before the platform replaces it
    (2-10). Lower reacts faster to bad instances; higher tolerates slow
    downstream dependencies.
  EOT
  default     = 5

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

variable "availability_test_enabled" {
  type        = bool
  description = <<-EOT
    Create a multi-region Application Insights URL-ping availability test
    against the health endpoint. Failures raise availability alerts inside
    Application Insights.
  EOT
  default     = true
}

variable "availability_test_locations" {
  type        = list(string)
  description = "Locations the availability test pings from."
  default     = ["us-va-ash-azr", "emea-nl-ams-azr", "apac-hk-hkn-azr"]
}

variable "availability_test_frequency_seconds" {
  type        = number
  description = "How often the availability test runs, in seconds (multiple of 60)."
  default     = 300

  validation {
    condition     = var.availability_test_frequency_seconds % 60 == 0 && var.availability_test_frequency_seconds >= 60
    error_message = "availability_test_frequency_seconds must be a positive multiple of 60."
  }
}

variable "availability_test_timeout_seconds" {
  type        = number
  description = "Per-request timeout of the availability test; must be below the frequency."
  default     = 30
}

variable "availability_test_expected_status_code" {
  type        = number
  description = "HTTP status code the availability test expects from the health endpoint."
  default     = 200
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "staging_slot_enabled" {
  type        = bool
  description = <<-EOT
    Create a staging deployment slot. Standard rollout path: ship the new image
    to the slot, verify against production dependencies, then swap it into
    production.
  EOT
  default     = true
}

variable "staging_slot_name" {
  type        = string
  description = "Name of the deployment slot used for staged rollouts."
  default     = "staging"
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  type        = number
  description = "Retention (days) in the Log Analytics workspace and Application Insights. 30-730."
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "additional_app_settings" {
  type        = map(string)
  description = <<-EOT
    Extra app settings merged over the module's defaults; per-service knobs that
    don't deserve their own variable. Keys the module manages (App Insights
    connection string, health-check tuning, registry credentials) win on conflict.
  EOT
  default     = {}
}
