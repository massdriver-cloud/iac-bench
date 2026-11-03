variable "app_name" {
  description = "Service name. Used to derive resource names. Lowercase letters, digits and hyphens; 2-40 chars; must start with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-40 chars, lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "container_registry_url" {
  description = "Registry URL that hosts the container image, e.g. https://myacr.azurecr.io or https://mcr.microsoft.com."
  type        = string
}

variable "container_image" {
  description = "Image name and tag within the registry, e.g. team/api:1.4.2. Tags must be pinned; 'latest' is rejected."
  type        = string

  validation {
    condition     = can(regex(":", var.container_image)) && !endswith(var.container_image, ":latest")
    error_message = "container_image must include a pinned tag (name:tag) and must not use 'latest'."
  }
}

variable "container_port" {
  description = "Port the container listens on inside the image. Exposed to App Service as WEBSITES_PORT."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port > 0 && var.container_port < 65536
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "sku_name" {
  description = "App Service plan SKU. Use P*v3 for production (zone redundancy and autoscale need it). B1 and above support autoscale only on S/P/I tiers; F1/D1 are not supported."
  type        = string
  default     = "P1v3"

  validation {
    condition     = contains(["B1", "B2", "B3", "S1", "S2", "S3", "P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3", "I1v2", "I2v2", "I3v2"], var.sku_name)
    error_message = "sku_name must be a supported Linux SKU (B1-B3, S1-S3, P0v3-P3v3, P1mv3-P3mv3, I1v2-I3v2)."
  }
}

variable "instance_count" {
  description = "Number of instances. Use at least 2 in production so a single instance failure does not take the service down."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 30
    error_message = "instance_count must be between 1 and 30."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires a premium v2/v3/v4 or isolated v2 SKU and at least 2 instances. Defaults on."
  type        = bool
  default     = true
}

variable "autoscale" {
  description = "Optional CPU-based autoscale for the plan. Null disables autoscale and the instance_count is fixed."
  type = object({
    min_instances     = number
    max_instances     = number
    scale_out_cpu_pct = optional(number, 70)
    scale_in_cpu_pct  = optional(number, 30)
  })
  default = null

  validation {
    condition     = var.autoscale == null ? true : (var.autoscale.min_instances >= 1 && var.autoscale.max_instances >= var.autoscale.min_instances && var.autoscale.max_instances <= 30)
    error_message = "autoscale: require 1 <= min_instances <= max_instances <= 30."
  }

  validation {
    condition     = var.autoscale == null ? true : (var.autoscale.scale_in_cpu_pct < var.autoscale.scale_out_cpu_pct && var.autoscale.scale_out_cpu_pct <= 100)
    error_message = "autoscale: scale_in_cpu_pct must be below scale_out_cpu_pct, and scale_out_cpu_pct at most 100."
  }
}

variable "health_check_path" {
  description = "HTTP path App Service polls to determine instance health. Must return 200 when the service is ready to take traffic."
  type        = string
  default     = "/healthz"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_eviction_minutes" {
  description = "Minutes an instance may fail health checks before App Service replaces it (2-10)."
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_eviction_minutes >= 2 && var.health_check_eviction_minutes <= 10
    error_message = "health_check_eviction_minutes must be between 2 and 10."
  }
}

variable "deployment_slot_enabled" {
  description = "Create a 'staging' deployment slot for blue/green style rollouts. Requires a Standard tier or above SKU."
  type        = bool
  default     = true
}

variable "app_settings" {
  description = "Additional application settings for the app and the staging slot."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "log_retention_days" {
  description = "Retention in days for the Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
