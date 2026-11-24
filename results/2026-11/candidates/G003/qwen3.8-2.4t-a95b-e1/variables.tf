# -----------------------------------------------------------------------------
# Identity: the only things an SRE must supply per service.
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Service name. Used as the App Service (and hostname prefix) name, and to derive sibling resource names. Lowercase letters, digits and hyphens."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,58}[a-z0-9])?$", var.name))
    error_message = "name must be 2-60 characters: lowercase letters, digits and hyphens, starting/ending alphanumeric."
  }
}

variable "location" {
  type        = string
  description = "Azure region for every resource in the module (e.g. westeurope). Pick a region with availability zones and the chosen SKU."
}

variable "image_name" {
  type        = string
  description = "Container image to run (repository path relative to the registry, e.g. 'product-team/orders-api' or 'azuredocs/aci-helloworld')."
}

variable "image_tag" {
  type        = string
  description = "Container image tag to run. Change this (via the staging slot + swap workflow) to roll out a new release."
}

# -----------------------------------------------------------------------------
# Placement.
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group the module creates for this service. Defaults to '<name>-rg' when null."
  default     = null
}

# -----------------------------------------------------------------------------
# Container image & registry.
# -----------------------------------------------------------------------------

variable "image_registry_url" {
  type        = string
  description = "Container registry server URL the image is pulled from."
  default     = "https://mcr.microsoft.com"
}

variable "container_port" {
  type        = number
  description = "Port the container listens on. Exported to the platform as WEBSITES_PORT."
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "container_registry_username" {
  type        = string
  description = "Username for a private registry (admin-user style auth). Leave null when the registry is public or you use managed-identity pull (container_registry_id)."
  default     = null
}

variable "container_registry_password" {
  type        = string
  description = "Password for a private registry. Leave null when the registry is public or you use managed-identity pull."
  default     = null
  sensitive   = true
}

variable "container_registry_id" {
  type        = string
  description = "Resource ID of an Azure Container Registry. When set, the app's system-assigned identity is granted AcrPull on it and the app pulls via managed identity. Leave null for public registries."
  default     = null
}

# -----------------------------------------------------------------------------
# Capacity & scaling.
# -----------------------------------------------------------------------------

variable "sku_name" {
  type        = string
  description = "App Service Plan SKU. Default P1v3 supports availability zones, scaling and production-grade workloads."
  default     = "P1v3"
}

variable "instance_count" {
  type        = number
  description = "Baseline instance count (also the autoscale default). Keep >= 3 to spread instances across availability zones."
  default     = 3

  validation {
    condition     = var.instance_count >= 1
    error_message = "instance_count must be >= 1."
  }
}

variable "zone_balancing_enabled" {
  type        = bool
  description = "Spread instances across availability zones for zone-level fault tolerance. Requires a zone-capable SKU/region."
  default     = true
}

variable "autoscale_enabled" {
  type        = bool
  description = "Attach a CPU-based autoscale policy to the plan. When false the plan stays at instance_count."
  default     = true
}

variable "autoscale_min_instances" {
  type        = number
  description = "Minimum instances for autoscale. Defaults to instance_count when null."
  default     = null

  validation {
    condition     = var.autoscale_min_instances == null || var.autoscale_min_instances >= 1
    error_message = "autoscale_min_instances must be >= 1."
  }
}

variable "autoscale_max_instances" {
  type        = number
  description = "Maximum instances autoscale may grow to under load."
  default     = 10

  validation {
    condition     = var.autoscale_max_instances >= 1
    error_message = "autoscale_max_instances must be >= 1."
  }
}

variable "scale_out_cpu_threshold" {
  type        = number
  description = "Average CPU percentage above which instances are added."
  default     = 70

  validation {
    condition     = var.scale_out_cpu_threshold > 0 && var.scale_out_cpu_threshold < 100
    error_message = "scale_out_cpu_threshold must be between 1 and 99."
  }
}

variable "scale_in_cpu_threshold" {
  type        = number
  description = "Average CPU percentage below which instances are removed."
  default     = 30

  validation {
    condition     = var.scale_in_cpu_threshold > 0 && var.scale_in_cpu_threshold < 100
    error_message = "scale_in_cpu_threshold must be between 1 and 99."
  }
}

# -----------------------------------------------------------------------------
# Health & self-healing.
# -----------------------------------------------------------------------------

variable "health_check_path" {
  type        = string
  description = "HTTP path App Service probes to verify instance health. Instances failing probes are evicted and replaced by the platform."
  default     = "/health"

  validation {
    condition     = substr(var.health_check_path, 0, 1) == "/"
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_minutes" {
  type        = number
  description = "Minutes an instance may fail health checks before it is evicted (2-10)."
  default     = 5

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10
    error_message = "health_check_eviction_minutes must be between 2 and 10."
  }
}

# -----------------------------------------------------------------------------
# Rollouts.
# -----------------------------------------------------------------------------

variable "staging_slot_enabled" {
  type        = bool
  description = "Create a 'staging' deployment slot for progressive rollouts (deploy, verify, swap)."
  default     = true
}

variable "auto_swap_enabled" {
  type        = bool
  description = "When true the staging slot auto-swaps into production after each deployment (hands-free rollout). When false swaps are explicit."
  default     = false
}

# -----------------------------------------------------------------------------
# Networking.
# -----------------------------------------------------------------------------

variable "virtual_network_subnet_id" {
  type        = string
  description = "Subnet resource ID for VNet integration (egress into your network). Leave null for no integration. The subnet must be delegated to Microsoft.Web/serverFarms."
  default     = null
}

# -----------------------------------------------------------------------------
# Observability.
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  description = "Existing Log Analytics workspace to centralize logs/metrics in. Leave null to create a dedicated workspace for this service."
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "Retention (days) applied to Log Analytics, Application Insights and diagnostic retention policies (30-730)."
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

# -----------------------------------------------------------------------------
# Overrides / escape hatches.
# -----------------------------------------------------------------------------

variable "additional_app_settings" {
  type        = map(string)
  description = "Extra app settings (injected as container environment variables). Merged after the module's defaults, so entries here win on conflict."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource, merged over the module's default tags."
  default     = {}
}
