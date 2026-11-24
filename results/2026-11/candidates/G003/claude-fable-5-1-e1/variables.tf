############################################
# Identity / placement
############################################

variable "name" {
  description = <<-EOT
    Base name of the service. Used as the Web App name (must be globally unique
    under *.azurewebsites.net) and as the prefix for every other resource the
    module creates (plan, Log Analytics, App Insights, alerts, ...).
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,58}[a-z0-9])?$", var.name))
    error_message = "name must be 2-60 chars, lowercase alphanumerics and hyphens, and must not start or end with a hyphen."
  }
}

variable "location" {
  description = "Azure region for all resources (e.g. \"westeurope\")."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into. Defaults to \"<name>-rg\" when null."
  type        = string
  default     = null
}

variable "create_resource_group" {
  description = "Create the resource group. Set to false to deploy into an existing one named by resource_group_name."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

############################################
# Container / workload
############################################

variable "container_image" {
  description = <<-EOT
    Container image reference *without* the registry host, e.g.
    "team/payments-api:1.4.2". The registry host is given separately via
    container_registry_url. Changing this value and applying is the standard
    rollout path (optionally via the staging slot and a swap).
  EOT
  type        = string

  validation {
    condition     = length(var.container_image) > 0 && !startswith(var.container_image, "http")
    error_message = "container_image must be a non-empty image[:tag] reference without a registry URL prefix."
  }
}

variable "container_registry_url" {
  description = "Registry URL the image is pulled from, including scheme. Defaults to Docker Hub."
  type        = string
  default     = "https://index.docker.io"

  validation {
    condition     = startswith(var.container_registry_url, "https://")
    error_message = "container_registry_url must start with https://."
  }
}

variable "container_registry_username" {
  description = "Username for a private registry. Leave null for anonymous pulls or when using managed identity against ACR."
  type        = string
  default     = null
}

variable "container_registry_password" {
  description = "Password / token for a private registry. Leave null for anonymous pulls or when using managed identity against ACR."
  type        = string
  default     = null
  sensitive   = true
}

variable "acr_id" {
  description = <<-EOT
    Resource ID of an Azure Container Registry. When set, the module grants the
    app's (and staging slot's) managed identity AcrPull on it and configures
    the app to pull with managed identity instead of registry credentials.
  EOT
  type        = string
  default     = null
}

variable "container_port" {
  description = "TCP port the container listens on. Exposed to the container as WEBSITES_PORT."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "container_start_time_limit_seconds" {
  description = "How long App Service waits for the container to respond on its port before marking the start as failed."
  type        = number
  default     = 230

  validation {
    condition     = var.container_start_time_limit_seconds >= 30 && var.container_start_time_limit_seconds <= 1800
    error_message = "container_start_time_limit_seconds must be between 30 and 1800."
  }
}

variable "app_settings" {
  description = "Non-secret environment variables for the container. Merged over the module's baseline settings (your keys win)."
  type        = map(string)
  default     = {}
}

variable "sensitive_app_settings" {
  description = "Secret environment variables for the container (kept out of plan output). Prefer Key Vault references, e.g. \"@Microsoft.KeyVault(SecretUri=...)\"."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "sticky_app_setting_names" {
  description = "App setting names that stay with the slot during a swap (slot-specific config). The App Insights connection string is always sticky."
  type        = list(string)
  default     = []
}

############################################
# Capacity / availability
############################################

variable "sku_name" {
  description = <<-EOT
    App Service Plan SKU. Premium v3 (P0v3..P3v3, P1mv3..P5mv3) is the
    production default. Standard (S1..S3) is acceptable. Basic (B1..B3) is
    dev-only: it supports neither autoscale, deployment slots nor zone
    redundancy, so capacity must be fixed (min == max).
  EOT
  type        = string
  default     = "P1v3"

  validation {
    condition     = can(regex("^(B[1-3]|S[1-3]|P[1-3]v2|P[0-3]v3|P[1-5]mv3)$", var.sku_name))
    error_message = "sku_name must be one of B1-B3, S1-S3, P1v2-P3v2, P0v3-P3v3 or P1mv3-P5mv3."
  }
}

variable "capacity" {
  description = <<-EOT
    Instance capacity of the plan. The module always manages instance count
    through an Azure Monitor autoscale setting (on Standard and above):
      - min == max  => fixed capacity, no scale rules.
      - max  > min  => CPU-driven autoscale between min and max
                       (scale out above scale_out_cpu_percent, in below
                       scale_in_cpu_percent).
  EOT
  type = object({
    min                   = optional(number, 2)
    max                   = optional(number, 4)
    scale_out_cpu_percent = optional(number, 70)
    scale_in_cpu_percent  = optional(number, 30)
  })
  default = {}

  validation {
    condition     = var.capacity.min >= 1 && var.capacity.max >= var.capacity.min && var.capacity.max <= 30
    error_message = "capacity.min must be >= 1, capacity.max must be >= capacity.min and <= 30."
  }

  validation {
    condition     = var.capacity.scale_in_cpu_percent < var.capacity.scale_out_cpu_percent && var.capacity.scale_out_cpu_percent <= 100 && var.capacity.scale_in_cpu_percent >= 0
    error_message = "scale_in_cpu_percent must be lower than scale_out_cpu_percent, both within 0-100."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires a Premium v2/v3 SKU, a region with zones, and capacity.min >= 3."
  type        = bool
  default     = false
}

############################################
# Health / rollouts
############################################

variable "health_check_path" {
  description = "HTTP path App Service probes on every instance. Instances that fail are removed from rotation and recycled."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_minutes" {
  description = "Minutes an instance may fail health checks before it is removed from the load balancer (2-10)."
  type        = number
  default     = 2

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10
    error_message = "health_check_eviction_minutes must be between 2 and 10."
  }
}

variable "enable_staging_slot" {
  description = "Create a \"staging\" deployment slot (same config, same image) for warm-up and swap-based rollouts. Requires Standard or above."
  type        = bool
  default     = false
}

############################################
# Networking
############################################

variable "vnet_integration_subnet_id" {
  description = "Subnet ID (delegated to Microsoft.Web/serverFarms) for regional VNet integration. All outbound traffic is routed through the VNet when set."
  type        = string
  default     = null
}

variable "allowed_ip_ranges" {
  description = "Inbound allow-list of CIDR ranges. When non-empty, all other sources are denied at the App Service front door."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_ip_ranges : can(cidrhost(c, 0))])
    error_message = "Every entry in allowed_ip_ranges must be a valid CIDR (e.g. 10.0.0.0/8)."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the app is reachable from the public internet. Set false when fronting it with a private endpoint managed elsewhere."
  type        = bool
  default     = true
}

############################################
# Observability
############################################

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace to send logs/metrics/App Insights telemetry to. A dedicated workspace is created when null."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention for the module-created Log Analytics workspace (ignored when bringing your own)."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "alerts" {
  description = <<-EOT
    Standard alert pack. When enabled, metric alerts for 5xx rate, p-average
    latency, health-check status, plan CPU and plan memory are created and
    routed to either action_group_id (bring your own) or a module-created
    action group that emails email_addresses.
  EOT
  type = object({
    enabled                      = optional(bool, true)
    action_group_id              = optional(string)
    email_addresses              = optional(list(string), [])
    http_5xx_count_per_5m        = optional(number, 10)
    response_time_seconds        = optional(number, 5)
    cpu_percent                  = optional(number, 85)
    memory_percent               = optional(number, 85)
    evaluation_frequency_minutes = optional(number, 1)
    window_minutes               = optional(number, 5)
  })
  default = {}

  validation {
    condition     = contains([1, 5, 15, 30, 60], var.alerts.evaluation_frequency_minutes) && contains([5, 15, 30, 60], var.alerts.window_minutes)
    error_message = "evaluation_frequency_minutes must be one of 1,5,15,30,60 and window_minutes one of 5,15,30,60."
  }
}
