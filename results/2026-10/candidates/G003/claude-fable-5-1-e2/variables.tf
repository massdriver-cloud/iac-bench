#############################################
# Identity of the service
#############################################

variable "name" {
  description = "Name of the service. Used as the globally-unique App Service name and as the prefix for every other resource the module creates."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,58}[a-z0-9])?$", var.name))
    error_message = "name must be 2-60 lowercase alphanumeric characters or hyphens, and must not start or end with a hyphen."
  }
}

variable "location" {
  description = "Azure region for all resources (e.g. eastus, westeurope)."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

#############################################
# Container / workload
#############################################

variable "container_image" {
  description = "Container image including tag, e.g. 'ghcr.io/acme/api:1.4.2' or 'myacr.azurecr.io/api:1.4.2'. The registry host is derived from the image reference; images without a host are pulled from Docker Hub. NOTE: this is the *initial* image. Rollouts are expected to go through the staging slot + swap, so the module ignores subsequent changes to the running image."
  type        = string

  validation {
    condition     = length(regexall(":", var.container_image)) >= 1 && !endswith(var.container_image, ":latest")
    error_message = "container_image must include an explicit, immutable tag (not ':latest')."
  }
}

variable "container_port" {
  description = "TCP port the container listens on for HTTP."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port > 0 && var.container_port < 65536
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "container_registry_id" {
  description = "Resource ID of an Azure Container Registry. When set, the module's managed identity is granted AcrPull on it and the app pulls using that identity (no registry credentials needed)."
  type        = string
  default     = null
}

variable "registry_username" {
  description = "Username for a private non-ACR registry. Leave null for public images or ACR via managed identity."
  type        = string
  default     = null
}

variable "registry_password" {
  description = "Password/token for a private non-ACR registry."
  type        = string
  default     = null
  sensitive   = true
}

variable "app_settings" {
  description = "Additional application settings (environment variables) injected into the container. Module-managed settings (port, App Insights, etc.) take precedence."
  type        = map(string)
  default     = {}
}

variable "sticky_app_setting_names" {
  description = "App setting keys that stay with the slot during a swap (e.g. settings that must differ between staging and production)."
  type        = list(string)
  default     = []
}

#############################################
# Capacity
#############################################

variable "sku_name" {
  description = "App Service plan SKU. Premium v3 (P0v3..P3v3) is recommended for production; Basic/Standard are allowed for non-critical services."
  type        = string
  default     = "P1v3"

  validation {
    condition     = contains(["B1", "B2", "B3", "S1", "S2", "S3", "P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "P4mv3", "P5mv3"], var.sku_name)
    error_message = "sku_name must be one of B1-B3, S1-S3, P0v3-P3v3 or P1mv3-P5mv3."
  }
}

variable "min_instances" {
  description = "Minimum (and initial) number of plan instances. Autoscale is configured when max_instances > min_instances."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 30
    error_message = "min_instances must be between 1 and 30."
  }
}

variable "max_instances" {
  description = "Maximum number of instances autoscale may scale out to. Set equal to min_instances to disable autoscale."
  type        = number
  default     = 5

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "autoscale_cpu_scale_out_percent" {
  description = "Average plan CPU % (over 10 minutes) above which one instance is added."
  type        = number
  default     = 70
}

variable "autoscale_cpu_scale_in_percent" {
  description = "Average plan CPU % (over 10 minutes) below which one instance is removed."
  type        = number
  default     = 30
}

#############################################
# Availability
#############################################

variable "zone_redundant" {
  description = "Spread plan instances across availability zones. Requires a Premium v3 SKU and min_instances >= 3."
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "HTTP path App Service probes on every instance. Instances failing the probe are removed from rotation and recycled."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may fail health checks before it is removed from the load balancer and restarted (2-10)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

#############################################
# Rollouts
#############################################

variable "staging_slot_enabled" {
  description = "Create a 'staging' deployment slot for blue/green rollouts (deploy to slot, verify, swap). Requires a Standard or Premium SKU."
  type        = bool
  default     = true
}

#############################################
# Networking
#############################################

variable "virtual_network_subnet_id" {
  description = "Subnet ID for regional VNet integration (outbound traffic from the app). Null disables VNet integration."
  type        = string
  default     = null
}

variable "allowed_ip_ranges" {
  description = "CIDR ranges allowed to reach the app. Empty list means public access from anywhere."
  type        = list(string)
  default     = []
}

variable "allowed_service_tags" {
  description = "Azure service tags (e.g. 'AzureFrontDoor.Backend') allowed to reach the app. Combined with allowed_ip_ranges; empty with no IP ranges means open access."
  type        = list(string)
  default     = []
}

#############################################
# Observability & alerting
#############################################

variable "log_retention_days" {
  description = "Retention in days for the Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "alert_email_addresses" {
  description = "Email addresses that receive alert notifications."
  type        = list(string)
  default     = []
}

variable "alert_webhook_url" {
  description = "Optional webhook (e.g. PagerDuty/Opsgenie/Slack) that receives alert notifications."
  type        = string
  default     = null
}

variable "alerts_enabled" {
  description = "Create the standard metric alerts (health check, 5xx rate, latency)."
  type        = bool
  default     = true
}

variable "alert_http_5xx_threshold" {
  description = "Number of 5xx responses in a 5 minute window that triggers the error alert."
  type        = number
  default     = 50
}

variable "alert_response_time_seconds" {
  description = "Average response time (seconds, 5 minute window) that triggers the latency alert."
  type        = number
  default     = 3
}
