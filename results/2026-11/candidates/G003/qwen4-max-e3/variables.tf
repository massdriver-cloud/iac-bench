###############################################################################
# Identity of the service
###############################################################################

variable "name" {
  description = "Name of the service. Used to name the web app and to derive the names of all supporting resources. Must be globally unique across Azure (it becomes part of the default hostname)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,58}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-60 characters, alphanumeric or hyphens, and must not start or end with a hyphen."
  }
}

variable "location" {
  description = "Azure region the service runs in."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group to create for this service. Defaults to '<name>-rg'."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource. The module always adds 'service' and 'managedBy' tags."
  type        = map(string)
  default     = {}
}

###############################################################################
# Workload: the container the service runs
###############################################################################

variable "container_image" {
  description = "Container image to run, in 'repository:tag' form, e.g. 'nginx:1.27' or 'myregistry.azurecr.io/payments-api:1.4.2'. Always pin a tag; never use 'latest' in production."
  type        = string

  validation {
    condition     = can(regex("^[^\\s]+:[^\\s]+$", var.container_image)) && !endswith(var.container_image, ":latest")
    error_message = "container_image must include an explicit tag and must not be ':latest'."
  }
}

variable "container_registry_url" {
  description = "Registry the image is pulled from, as a URL. Defaults to Docker Hub. For ACR use 'https://<registry>.azurecr.io'."
  type        = string
  default     = "https://index.docker.io"
}

variable "container_registry_username" {
  description = "Username for a private registry using basic credentials. Leave null for public images or managed-identity pulls."
  type        = string
  default     = null
}

variable "container_registry_password" {
  description = "Password/token for a private registry. Only used when container_registry_username is set."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_registry_use_managed_identity" {
  description = "Pull the image using the app's system-assigned managed identity (recommended for ACR: grant AcrPull to the principal_id / staging_principal_id outputs). Mutually exclusive with registry username/password."
  type        = bool
  default     = false
}

variable "container_port" {
  description = "Port the container listens on. App Service routes external HTTPS traffic to this port (WEBSITES_PORT)."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port (1-65535)."
  }
}

variable "startup_command" {
  description = "Optional startup command override for the container. Leave null to use the image's entrypoint."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Application settings (environment variables) for the service, in addition to the ones the module manages (port, App Insights, registry credentials, ENVIRONMENT). Platform-managed keys take precedence."
  type        = map(string)
  default     = {}
}

###############################################################################
# Capacity and availability
###############################################################################

variable "sku_name" {
  description = "App Service plan SKU. Defaults to P1v3 (production grade: autoscale, slots, zone redundancy support). Use B* only for dev/test (with autoscale_enabled = false and staging_slot_enabled = false)."
  type        = string
  default     = "P1v3"
}

variable "instance_count" {
  description = "Baseline number of workers. With autoscale enabled this is the default capacity the plan starts at; otherwise it is the fixed worker count."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 30
    error_message = "instance_count must be between 1 and 30."
  }
}

variable "autoscale_enabled" {
  description = "Manage worker count with CPU-based autoscaling instead of a fixed instance count. Requires a Standard or higher SKU."
  type        = bool
  default     = true
}

variable "autoscale_min_instances" {
  description = "Autoscale floor. Keep >= 2 for production availability (>= 3 with zone balancing)."
  type        = number
  default     = 2
}

variable "autoscale_max_instances" {
  description = "Autoscale ceiling (cost guardrail)."
  type        = number
  default     = 6
}

variable "zone_balancing_enabled" {
  description = "Spread workers across availability zones. Requires a Premium v2/v3 SKU and at least 3 instances (the module enforces both)."
  type        = bool
  default     = false
}

###############################################################################
# Health
###############################################################################

variable "health_check_path" {
  description = "HTTP path App Service probes on every instance. Instances failing the probe are removed from load balancer rotation. Point this at a real readiness endpoint."
  type        = string
  default     = "/"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_time_in_min" {
  description = "How long an instance may continuously fail the health probe before it is replaced (2-10 minutes)."
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10."
  }
}

###############################################################################
# Rollouts
###############################################################################

variable "staging_slot_enabled" {
  description = "Create a 'staging' deployment slot running the same image/config. Deploy new versions to staging, warm them up, then swap into production (the swap is performed by your release pipeline, e.g. 'az webapp deployment slot swap')."
  type        = bool
  default     = true
}

###############################################################################
# Networking
###############################################################################

variable "vnet_integration_subnet_id" {
  description = "Optional subnet ID for regional VNet integration (outbound traffic). The subnet must be delegated to Microsoft.Web/serverFarms. When set, all outbound traffic is routed through the VNet."
  type        = string
  default     = null
}

###############################################################################
# Observability
###############################################################################

variable "log_retention_days" {
  description = "Retention (days) for the service's Log Analytics workspace and App Insights data."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "daily_log_cap_gb" {
  description = "Daily ingestion cap for the Log Analytics workspace in GB (cost guardrail). -1 disables the cap."
  type        = number
  default     = 1
}
