############ Identity / placement ############

variable "name" {
  description = "Service name. Used as the web app name (must be globally unique, becomes <name>.azurewebsites.net) and as the base for all related resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "name must be 2-40 characters, lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "create_resource_group" {
  description = "Create a resource group for the service. Set to false to deploy into an existing one named by resource_group_name."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Resource group name. Defaults to rg-<name>. Must already exist when create_resource_group is false."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

############ Container ############

variable "container_image" {
  description = "Image repository path without registry host or tag, e.g. 'myteam/orders-api'."
  type        = string
}

variable "container_image_tag" {
  description = "Image tag to deploy. Prefer immutable tags (version or digest-style tags) over 'latest'."
  type        = string
  default     = "latest"
}

variable "container_registry_url" {
  description = "Registry URL, e.g. 'https://myacr.azurecr.io' or 'https://mcr.microsoft.com'."
  type        = string
  default     = "https://mcr.microsoft.com"
}

variable "container_registry_use_managed_identity" {
  description = "Pull the image using the app's system-assigned managed identity (use for ACR; grant the identity AcrPull separately via the exported principal id)."
  type        = bool
  default     = false
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80

  validation {
    condition     = var.container_port > 0 && var.container_port < 65536
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "app_settings" {
  description = "Additional (non-secret) application settings / environment variables."
  type        = map(string)
  default     = {}
}

############ Capacity ############

variable "sku_name" {
  description = "App Service plan SKU. Must be Standard or Premium (S*, P*v2, P*v3, P*mv3) for autoscale, slots and zone redundancy (Premium only)."
  type        = string
  default     = "P1v3"

  validation {
    condition     = can(regex("^(S[1-3]|P[1-3]v[23]|P[1-5]mv3)$", var.sku_name))
    error_message = "sku_name must be a Standard or Premium SKU such as S1, P1v3, P2v3 or P1mv3."
  }
}

variable "min_instances" {
  description = "Minimum instance count (autoscale floor). Use 2 or more for availability."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 30
    error_message = "min_instances must be between 1 and 30."
  }
}

variable "max_instances" {
  description = "Maximum instance count (autoscale ceiling)."
  type        = number
  default     = 6

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "autoscale_cpu_scale_out_threshold" {
  description = "Average CPU % over 10 minutes above which an instance is added."
  type        = number
  default     = 70
}

variable "autoscale_cpu_scale_in_threshold" {
  description = "Average CPU % over 10 minutes below which an instance is removed."
  type        = number
  default     = 30
}

############ Availability ############

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires a Premium v2/v3 SKU, a region with zones, and min_instances >= 2 (the plan is created with min_instances)."
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "HTTP path App Service probes to determine instance health. Unhealthy instances are removed from rotation and replaced."
  type        = string
  default     = "/"
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may fail health checks before being removed from the load balancer (2-10)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

############ Rollouts ############

variable "enable_staging_slot" {
  description = "Create a 'staging' deployment slot for warm-up and swap-based, zero-downtime releases."
  type        = bool
  default     = true
}

variable "staging_container_image_tag" {
  description = "Image tag deployed to the staging slot. Defaults to container_image_tag. Pipelines normally update this and then swap."
  type        = string
  default     = null
}

############ Networking / security ############

variable "allowed_ip_ranges" {
  description = "CIDR ranges allowed to reach the app. Empty means open to all (public). When set, all other traffic is denied."
  type        = list(string)
  default     = []
}

variable "minimum_tls_version" {
  description = "Minimum inbound TLS version."
  type        = string
  default     = "1.2"

  validation {
    condition     = contains(["1.2", "1.3"], var.minimum_tls_version)
    error_message = "minimum_tls_version must be 1.2 or 1.3."
  }
}

############ Observability ############

variable "log_retention_days" {
  description = "Retention in days for the Log Analytics workspace."
  type        = number
  default     = 30
}

variable "alert_email_addresses" {
  description = "Email addresses notified by alerts. If empty, alerts are still created but notify nobody (visible in the portal)."
  type        = list(string)
  default     = []
}

variable "alert_http_5xx_threshold" {
  description = "Total HTTP 5xx responses in 5 minutes that trigger an alert."
  type        = number
  default     = 10
}

variable "alert_response_time_seconds" {
  description = "Average response time (seconds) over 5 minutes that triggers an alert."
  type        = number
  default     = 2
}
