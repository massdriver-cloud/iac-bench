# -----------------------------------------------------------------------------
# Service identity and placement
# -----------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription to deploy into. Leave null to use the ARM_* environment credentials (recommended)."
  type        = string
  default     = null
}

variable "name" {
  description = <<-EOT
    Name of the service. It is the naming stem for every resource created by
    this module: rg-<name>, plan-<name>, app-<name>, log-<name>, appi-<name>.

    The web app name (app-<name>) must be globally unique in Azure, so use a
    distinctive, org-qualified name per service (e.g. 'orders-api-prod').
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{2,39}$", var.name))
    error_message = "name must be 3-40 characters of letters, digits and hyphens and must start with a letter or digit."
  }
}

variable "location" {
  description = "Azure region for the service. Use a region with availability zones (e.g. westeurope, eastus): Premium v3 plans are zone-redundant there, and the default of 3 instances spreads across the zones."
  type        = string
}

# -----------------------------------------------------------------------------
# Container image
# -----------------------------------------------------------------------------

variable "container_image" {
  description = "Image the service runs, as '<repository>:<tag>' relative to the registry host (e.g. 'orders/api:1.4.2')."
  type        = string

  validation {
    condition     = length(var.container_image) > 0
    error_message = "container_image must not be empty."
  }
}

variable "container_registry_id" {
  description = <<-EOT
    Resource ID of the Azure Container Registry that hosts the image, e.g.
    /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerRegistry/registries/<registry>.
    When set, the app and every slot pull with their managed identities, are
    granted AcrPull on the registry, and the registry URL is derived from it.
  EOT
  type        = string
  default     = null

  validation {
    condition = var.container_registry_id == null || can(
      regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.containerregistry/registries/[^/]+$", var.container_registry_id)
    )
    error_message = "container_registry_id must be the full resource ID of an Azure Container Registry."
  }
}

variable "container_registry_url" {
  description = "Explicit registry URL with scheme (e.g. 'https://ghcr.io'). Defaults to the ACR URL derived from container_registry_id, or to the public Microsoft registry when no registry ID is given."
  type        = string
  default     = null
}

variable "container_port" {
  description = "TCP port the container listens on; App Service routes traffic to it (injected as WEBSITES_PORT)."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

# -----------------------------------------------------------------------------
# Health
# -----------------------------------------------------------------------------

variable "health_check_path" {
  description = "HTTP path the service exposes for liveness, e.g. '/health'. App Service probes it continuously: instances that fail for health_check_eviction_minutes are removed from the load balancer and replaced, and auto-swap (when enabled) waits for it."
  type        = string

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_minutes" {
  description = "Minutes an instance may fail health checks before it is evicted and replaced."
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 20
    error_message = "health_check_eviction_minutes must be between 2 and 20."
  }
}

# -----------------------------------------------------------------------------
# Capacity
# -----------------------------------------------------------------------------

variable "instance_size" {
  description = <<-EOT
    Compute class per instance:
      small  -> P1v3  (2 vCPU, 3.5 GiB)
      medium -> P2v3  (4 vCPU, 7 GiB)
      large  -> P3v3  (8 vCPU, 14 GiB)
    All classes are Premium v3, the floor of the standard: Linux containers,
    autoscale and zone redundancy in zone-capable regions.
  EOT
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.instance_size)
    error_message = "instance_size must be one of: small, medium, large (use instance_sku for anything else)."
  }
}

variable "instance_sku" {
  description = "Escape hatch for services with unusual needs: an exact App Service SKU (e.g. 'P1mv3' memory-optimized). Takes precedence over instance_size."
  type        = string
  default     = null
}

variable "min_instances" {
  description = "Instances kept running at all times (the autoscale floor). The default of 3 matches the three availability zones a Premium v3 plan spreads over."
  type        = number
  default     = 3

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 100
    error_message = "min_instances must be between 1 and 100."
  }
}

variable "max_instances" {
  description = "Autoscale ceiling for instances. Set it equal to min_instances to pin capacity."
  type        = number
  default     = 10

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 100
    error_message = "max_instances must be between 1 and 100."
  }
}

variable "cpu_scale_out_threshold" {
  description = "Average CPU percentage sustained for 10 minutes that adds instances."
  type        = number
  default     = 70

  validation {
    condition     = var.cpu_scale_out_threshold > 0 && var.cpu_scale_out_threshold < 100
    error_message = "cpu_scale_out_threshold must be between 1 and 99."
  }
}

variable "cpu_scale_in_threshold" {
  description = "Average CPU percentage sustained for 15 minutes that removes instances."
  type        = number
  default     = 30

  validation {
    condition     = var.cpu_scale_in_threshold > 0 && var.cpu_scale_in_threshold < 100
    error_message = "cpu_scale_in_threshold must be between 1 and 99."
  }
}

# -----------------------------------------------------------------------------
# Rollouts
# -----------------------------------------------------------------------------

variable "deployment_slots" {
  description = "Warm deployment slots created next to production (same configuration, same identity rights, full logging). CI stages new versions here before promotion."
  type        = list(string)
  default     = ["staging"]

  validation {
    condition     = alltrue([for s in var.deployment_slots : can(regex("^[a-z0-9][a-z0-9-]{0,29}$", s))])
    error_message = "slot names must be 1-30 lowercase letters, digits or hyphens, starting with a letter or digit."
  }
}

variable "auto_swap_to_production" {
  description = "Promote a slot to production automatically once it is warm and its health check passes. Set to false to promote explicitly with 'az webapp deployment slot swap'."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "app_settings" {
  description = "Environment variables for the container, merged over the module defaults (WEBSITES_PORT, APPLICATIONINSIGHTS_CONNECTION_STRING, ...), so these win. Marked sensitive: prefer Key Vault references for real secrets."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "log_retention_in_days" {
  description = "Retention for the Log Analytics workspace that receives the service's logs and metrics."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_in_days >= 7 && var.log_retention_in_days <= 730
    error_message = "log_retention_in_days must be between 7 and 730."
  }
}

variable "app_insights_sampling_percentage" {
  description = "Ingestion sampling for Application Insights (100 = keep all telemetry)."
  type        = number
  default     = 100

  validation {
    condition     = var.app_insights_sampling_percentage >= 0 && var.app_insights_sampling_percentage <= 100
    error_message = "app_insights_sampling_percentage must be between 0 and 100."
  }
}

# -----------------------------------------------------------------------------
# Networking and tagging
# -----------------------------------------------------------------------------

variable "vnet_integration_subnet_id" {
  description = "Optional subnet ID for VNet integration; the subnet must be delegated to Microsoft.Web and dedicated to this plan. When set, all container egress is routed through the VNet."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource. The module adds a 'service' tag automatically; entries here override it."
  type        = map(string)
  default     = {}
}
