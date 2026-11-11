# =============================================================================
# Identity & placement
# =============================================================================

variable "name" {
  description = "Name of the service. Used directly as the App Service DNS label (must be globally unique in azurewebsites.net) and as the naming base for all supporting resources (rg-<name>, plan-<name>, appi-<name>, ...)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 characters of lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "location" {
  description = "Azure region the service runs in, e.g. westeurope. Must support availability zones if zone_redundant is true."
  type        = string
}

variable "resource_group_name" {
  description = "Deploy into this existing resource group. Leave null (default) to let the module create and own rg-<name>."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to every resource, merged over the module's own service and managed_by tags."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Container
# =============================================================================

variable "container_image" {
  description = "Container image to run, including the registry host, e.g. myregistry.azurecr.io/team/api or nginx for Docker Hub."
  type        = string
}

variable "container_tag" {
  description = "Tag (or digest) of the container image to run. Prefer immutable tags or digests for reproducible rollouts."
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "TCP port the container listens on. Set as WEBSITES_PORT so App Service routes traffic to the right port."
  type        = number
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be a TCP port between 1 and 65535."
  }
}

variable "container_registry_id" {
  description = "Resource ID of the Azure Container Registry hosting the image. When set, the app and the staging slot pull with their system-assigned managed identities and are granted AcrPull automatically. Mutually exclusive with basic-auth registry credentials."
  type        = string
  default     = null
}

variable "container_registry_url" {
  description = "Registry server URL for basic-auth registries (e.g. https://index.docker.io). Required when container_registry_username/password are used."
  type        = string
  default     = null
}

variable "container_registry_username" {
  description = "Username for a basic-auth container registry."
  type        = string
  default     = null
}

variable "container_registry_password" {
  description = "Password for a basic-auth container registry."
  type        = string
  default     = null
  sensitive   = true
}

# =============================================================================
# Capacity
# =============================================================================

variable "instance_size" {
  description = "App Service plan SKU (instance size). Only the Pv3, Pmv3 and Premium Container families support availability zones."
  type        = string
  default     = "P1v3"

  validation {
    condition     = contains(["B1", "B2", "B3", "S1", "S2", "S3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "PC2", "PC3", "PC4"], var.instance_size)
    error_message = "instance_size must be one of B1-B3, S1-S3, P1v3-P3v3, P1mv3-P3mv3 or PC2-PC4."
  }
}

variable "min_instances" {
  description = "Minimum number of instances the autoscaler keeps running. Must be >= 3 when zone_redundant is true (one instance per zone)."
  type        = number
  default     = 3

  validation {
    condition     = var.min_instances >= 1
    error_message = "min_instances must be at least 1."
  }
}

variable "max_instances" {
  description = "Maximum number of instances the autoscaler may scale out to. Set equal to min_instances for a fixed-size deployment."
  type        = number
  default     = 10

  validation {
    condition     = var.max_instances >= var.min_instances
    error_message = "max_instances must be greater than or equal to min_instances."
  }
}

variable "scale_out_cpu_percent" {
  description = "Scale out when average worker CPU utilization exceeds this percentage."
  type        = number
  default     = 70

  validation {
    condition     = var.scale_out_cpu_percent > 0 && var.scale_out_cpu_percent < 100
    error_message = "scale_out_cpu_percent must be between 1 and 99."
  }
}

variable "scale_in_cpu_percent" {
  description = "Scale in when average worker CPU utilization falls below this percentage."
  type        = number
  default     = 25

  validation {
    condition     = var.scale_in_cpu_percent > 0 && var.scale_in_cpu_percent < 100
    error_message = "scale_in_cpu_percent must be between 1 and 99."
  }
}

variable "scale_out_memory_percent" {
  description = "Scale out when average worker memory utilization exceeds this percentage."
  type        = number
  default     = 85

  validation {
    condition     = var.scale_out_memory_percent > 0 && var.scale_out_memory_percent < 100
    error_message = "scale_out_memory_percent must be between 1 and 99."
  }
}

variable "scale_out_http_queue_length" {
  description = "Scale out when the average number of queued HTTP requests exceeds this value (request backpressure)."
  type        = number
  default     = 100

  validation {
    condition     = var.scale_out_http_queue_length >= 1
    error_message = "scale_out_http_queue_length must be at least 1."
  }
}

# =============================================================================
# Availability
# =============================================================================

variable "zone_redundant" {
  description = "Spread instances across availability zones (requires a Pv3/Pmv3/PC SKU, at least 3 instances, and a zone-capable region)."
  type        = bool
  default     = true
}

# =============================================================================
# Health
# =============================================================================

variable "health_check_path" {
  description = "HTTP path App Service polls on every instance to decide whether it may receive traffic. Instances failing the probe are removed from the load balancer and eventually restarted. Also used as the synthetic availability probe path. Set to \"\" to disable."
  type        = string
  default     = "/healthz"
}

# =============================================================================
# Rollout
# =============================================================================

variable "enable_staging_slot" {
  description = "Create a `staging` deployment slot for blue/green rollouts. Slots run on the same plan, so there is no extra instance cost."
  type        = bool
  default     = true
}

variable "enable_auto_swap" {
  description = "Auto-swap `staging` into production as soon as it is warmed up. Intended for CI pipelines that deploy a new image to staging and let App Service complete the cutover."
  type        = bool
  default     = false
}

variable "sticky_app_settings" {
  description = "App setting names that must stay with their slot during a swap, e.g. settings that point staging at non-production dependencies."
  type        = list(string)
  default     = []
}

# =============================================================================
# Observability
# =============================================================================

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace resource ID to send logs and metrics to. Leave null (default) to create and own log-<name>."
  type        = string
  default     = null
}

variable "log_retention_in_days" {
  description = "Interactive retention in days for the module-created Log Analytics workspace. Ignored when an existing workspace is supplied."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_in_days >= 30 && var.log_retention_in_days <= 730
    error_message = "log_retention_in_days must be between 30 and 730."
  }
}

variable "app_insights_sampling_percent" {
  description = "Application Insights sampling percentage (0-100). Lower this on very high-volume APIs to control cost."
  type        = number
  default     = 100

  validation {
    condition     = var.app_insights_sampling_percent >= 0 && var.app_insights_sampling_percent <= 100
    error_message = "app_insights_sampling_percent must be between 0 and 100."
  }
}

variable "alert_emails" {
  description = "On-call email addresses paged by the module's alerts (HTTP 5xx, response time, CPU, memory) and notified of autoscale actions. Required: the module refuses to deploy an unmonitored service."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0 && alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "alert_emails must contain at least one valid email address."
  }
}

variable "alert_webhook_url" {
  description = "Optional webhook (PagerDuty, Opsgenie, Teams, ...) added to the action group in addition to alert_emails."
  type        = string
  default     = null
}

variable "alert_http_5xx_count" {
  description = "Page when the app serves more than this many HTTP 5xx responses in 5 minutes."
  type        = number
  default     = 10

  validation {
    condition     = var.alert_http_5xx_count >= 0
    error_message = "alert_http_5xx_count must be zero or more."
  }
}

variable "alert_response_time_seconds" {
  description = "Page when average response time exceeds this many seconds over 5 minutes."
  type        = number
  default     = 5

  validation {
    condition     = var.alert_response_time_seconds > 0
    error_message = "alert_response_time_seconds must be greater than zero."
  }
}

variable "alert_cpu_percent" {
  description = "Page when worker CPU stays above this percentage for 10 minutes, i.e. autoscaling is not keeping up."
  type        = number
  default     = 80

  validation {
    condition     = var.alert_cpu_percent > 0 && var.alert_cpu_percent < 100
    error_message = "alert_cpu_percent must be between 1 and 99."
  }
}

variable "alert_memory_percent" {
  description = "Page when worker memory stays above this percentage for 10 minutes."
  type        = number
  default     = 90

  validation {
    condition     = var.alert_memory_percent > 0 && var.alert_memory_percent < 100
    error_message = "alert_memory_percent must be between 1 and 99."
  }
}

variable "enable_availability_test" {
  description = "Run a multi-region synthetic test against the app's health endpoint every 5 minutes. Automatically disabled when the app is not publicly reachable (IP restrictions or public network access disabled)."
  type        = bool
  default     = true
}

variable "availability_test_locations" {
  description = "Azure Monitor geo-locations the synthetic availability test runs from."
  type        = list(string)
  default     = ["us-tx-sn1-azr", "us-il-ch1-azr", "emea-gb-db3-azr"]

  validation {
    condition     = length(var.availability_test_locations) > 0
    error_message = "availability_test_locations must contain at least one location."
  }
}

# =============================================================================
# Application configuration & networking
# =============================================================================

variable "app_settings" {
  description = "Environment variables injected into the container. Values may be Key Vault references (@Microsoft.KeyVault(...)) since the app runs with a system-assigned identity. Module-managed settings (WEBSITES_PORT, Application Insights wiring, registry credentials) always win."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "cors_allowed_origins" {
  description = "Origins allowed to call the API cross-origin (CORS). Empty list (default) leaves CORS unconfigured."
  type        = list(string)
  default     = []
}

variable "public_network_access_enabled" {
  description = "Whether the app is reachable from the public internet. Set false when the app is only called through VNet integration or a private front door."
  type        = bool
  default     = true
}

variable "allowed_ip_address_ranges" {
  description = "CIDR ranges allowed to reach the app and the staging slot. Empty list (default) means unrestricted. Setting any range automatically disables the synthetic availability test, which could no longer reach the app."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.allowed_ip_address_ranges : can(cidrnetmask(r))])
    error_message = "allowed_ip_address_ranges must contain valid CIDR blocks, e.g. 203.0.113.0/24."
  }
}

variable "vnet_integration_subnet_id" {
  description = "Subnet resource ID to integrate the app (and staging slot) with a VNet, e.g. to reach private backends. When set, all outbound traffic is routed through the VNet."
  type        = string
  default     = null
}
