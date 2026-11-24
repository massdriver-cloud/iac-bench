########################################
# Identity / placement
########################################

variable "name" {
  description = "Service name. Used as the (globally unique) Web App name and as the prefix for every other resource. Lowercase letters, digits and hyphens only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$", var.name))
    error_message = "name must be 3-60 characters of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "location" {
  description = "Azure region for all resources (e.g. westeurope)."
  type        = string
}

variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into. Leave null to have the module create '<name>-rg'."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

########################################
# Workload
########################################

variable "container_image" {
  description = "Container image for production, including tag or digest (e.g. 'myacr.azurecr.io/payments-api:1.4.2' or 'ghcr.io/org/api:1.4.2')."
  type        = string

  validation {
    condition     = can(regex("[:@]", var.container_image))
    error_message = "container_image must include an explicit tag or digest; floating images are not allowed."
  }
}

variable "staging_container_image" {
  description = "Container image for the staging slot. Leave null to run the same image as production (so a slot swap is configuration-neutral). Set it to the candidate image during a rollout."
  type        = string
  default     = null
}

variable "container_registry_url" {
  description = "Registry base URL (e.g. 'https://myacr.azurecr.io'). Leave null for Docker Hub / public registries."
  type        = string
  default     = null
}

variable "container_registry_id" {
  description = "Resource ID of an Azure Container Registry. When set, the module grants the app's managed identity AcrPull on it and configures identity-based pulls (no registry credentials)."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Port the container listens on. App Service routes HTTP traffic to it."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port > 0 && var.container_port < 65536
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "container_start_time_limit_seconds" {
  description = "How long App Service waits for the container to respond before declaring a failed start."
  type        = number
  default     = 230

  validation {
    condition     = var.container_start_time_limit_seconds >= 60 && var.container_start_time_limit_seconds <= 1800
    error_message = "container_start_time_limit_seconds must be between 60 and 1800."
  }
}

variable "app_settings" {
  description = "Application settings (environment variables) for the service. Key Vault references ('@Microsoft.KeyVault(...)') are supported. Platform settings managed by the module take precedence."
  type        = map(string)
  default     = {}
}

variable "sticky_app_setting_names" {
  description = "App setting keys that must NOT move between slots on swap (e.g. slot-specific feature flags)."
  type        = list(string)
  default     = []
}

########################################
# Capacity
########################################

variable "sku_name" {
  description = "App Service Plan SKU. PremiumV3 (P0v3..P3v3) or PremiumV2 recommended for production; zone redundancy requires PremiumV3 or higher."
  type        = string
  default     = "P1v3"

  validation {
    condition     = can(regex("^(B[1-3]|S[1-3]|P[1-3]v2|P[0-5]v3|P[1-3]mv3|I[1-6]v2|I[1-6]mv2)$", var.sku_name))
    error_message = "sku_name must be a Basic, Standard, PremiumV2, PremiumV3 or IsolatedV2 SKU (e.g. B1, S1, P1v2, P1v3, P1mv3, I1v2)."
  }
}

variable "instance_count" {
  description = "Number of plan instances. Doubles as the autoscale default/minimum when autoscale is enabled."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 30
    error_message = "instance_count must be between 1 and 30."
  }
}

variable "autoscale" {
  description = <<-EOT
    CPU-based autoscale for the plan. Set to null to run a fixed instance_count.
      max_instances            - upper bound for scale-out
      scale_out_cpu_percent    - average plan CPU (over 5 min) that triggers +1 instance
      scale_in_cpu_percent     - average plan CPU (over 10 min) that triggers -1 instance
  EOT
  type = object({
    max_instances         = number
    scale_out_cpu_percent = optional(number, 70)
    scale_in_cpu_percent  = optional(number, 30)
  })
  default = null

  validation {
    condition     = var.autoscale == null ? true : var.autoscale.scale_in_cpu_percent < var.autoscale.scale_out_cpu_percent
    error_message = "autoscale.scale_in_cpu_percent must be lower than scale_out_cpu_percent."
  }
}

########################################
# Availability
########################################

variable "zone_redundant" {
  description = "Spread plan instances across availability zones. Requires a PremiumV3/IsolatedV2 SKU, a region with zone support and instance_count >= 2."
  type        = bool
  default     = false

  validation {
    condition     = !var.zone_redundant || var.instance_count >= 2
    error_message = "zone_redundant requires instance_count >= 2."
  }
}

variable "staging_slot_enabled" {
  description = "Create a 'staging' deployment slot for swap-based rollouts. Requires a Standard tier or higher SKU."
  type        = bool
  default     = true
}

########################################
# Health
########################################

variable "health_check_path" {
  description = "HTTP path App Service probes on every instance. Instances that fail are removed from rotation and recycled."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may fail health checks before it is evicted and replaced."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

########################################
# Network / access
########################################

variable "public_network_access_enabled" {
  description = "Whether the app is reachable from the public internet. Set false when fronting it with Private Endpoints / Front Door Private Link."
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "CIDR ranges allowed to reach the app. Empty list = allow all. When non-empty everything else is denied."
  type        = list(string)
  default     = []
}

variable "allowed_service_tags" {
  description = "Azure service tags allowed to reach the app (e.g. ['AzureFrontDoor.Backend']). Combined with allowed_ip_ranges."
  type        = list(string)
  default     = []
}

variable "vnet_integration_subnet_id" {
  description = "Subnet ID (delegated to Microsoft.Web/serverFarms) for regional VNet integration of outbound traffic. Null = no integration."
  type        = string
  default     = null
}

########################################
# Observability
########################################

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace to send logs, metrics and Application Insights telemetry to. Leave null to have the module create one."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention for the module-created Log Analytics workspace. Ignored when log_analytics_workspace_id is supplied."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "alerts_enabled" {
  description = "Create the baseline metric alerts (HTTP 5xx rate, response time, health-check status)."
  type        = bool
  default     = true
}

variable "alert_action_group_ids" {
  description = "Action group IDs to notify when a baseline alert fires."
  type        = list(string)
  default     = []
}

variable "alert_http_5xx_threshold" {
  description = "Number of HTTP 5xx responses in a 5-minute window that fires the 5xx alert."
  type        = number
  default     = 50
}

variable "alert_response_time_threshold_seconds" {
  description = "Average response time (seconds, over 5 minutes) that fires the latency alert."
  type        = number
  default     = 2
}
