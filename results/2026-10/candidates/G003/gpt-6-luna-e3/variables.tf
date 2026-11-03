variable "app_name" {
  description = "Globally unique App Service name; also used as the resource-name prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,60}$", var.app_name))
    error_message = "app_name must be 2-60 characters and contain only letters, numbers, and hyphens."
  }
}

variable "location" {
  description = "Azure region for the service resources."
  type        = string
}

variable "container_image" {
  description = "Container image and optional tag, for example my-api:1.2.3."
  type        = string
}

variable "container_registry_url" {
  description = "Container registry endpoint. Use https://index.docker.io for Docker Hub."
  type        = string
  default     = "https://index.docker.io"
}

variable "container_registry_username" {
  description = "Optional username for a private container registry."
  type        = string
  default     = null
}

variable "container_registry_password" {
  description = "Optional password/token for a private container registry. Prefer secret-backed input values."
  type        = string
  sensitive   = true
  default     = null
}

variable "container_port" {
  description = "HTTP port exposed by the container."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "sku_name" {
  description = "Linux App Service plan SKU. Choose a production SKU that supports the desired capabilities."
  type        = string
  default     = "P1v3"
}

variable "worker_count" {
  description = "Initial/default number of plan workers."
  type        = number
  default     = 1

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

variable "zone_redundant" {
  description = "Enable zone balancing for the App Service plan."
  type        = bool
  default     = false
}

variable "enable_autoscale" {
  description = "Enable CPU-based autoscaling of the App Service plan."
  type        = bool
  default     = true
}

variable "autoscale_min_workers" {
  description = "Lower worker bound for autoscaling."
  type        = number
  default     = 1
}

variable "autoscale_max_workers" {
  description = "Upper worker bound for autoscaling."
  type        = number
  default     = 3

  validation {
    condition     = var.autoscale_max_workers >= var.autoscale_min_workers
    error_message = "autoscale_max_workers must be greater than or equal to autoscale_min_workers."
  }
}

variable "scale_out_cpu_threshold" {
  description = "Scale out when average CPU is greater than this percentage."
  type        = number
  default     = 70

  validation {
    condition     = var.scale_out_cpu_threshold >= 0 && var.scale_out_cpu_threshold <= 100
    error_message = "CPU thresholds must be percentages between 0 and 100."
  }
}

variable "scale_in_cpu_threshold" {
  description = "Scale in when average CPU is less than this percentage."
  type        = number
  default     = 30

  validation {
    condition     = var.scale_in_cpu_threshold >= 0 && var.scale_in_cpu_threshold <= 100
    error_message = "CPU thresholds must be percentages between 0 and 100."
  }
}

variable "health_check_path" {
  description = "HTTP health-check endpoint exposed by the application."
  type        = string
  default     = "/health"
}

variable "integration_subnet_id" {
  description = "Optional delegated subnet ID for regional VNet integration."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Additional application settings; values are strings and override module defaults."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Log Analytics retention period."
  type        = number
  default     = 30
}

variable "log_daily_quota_gb" {
  description = "Daily Log Analytics ingestion quota in GB; -1 disables the quota."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Additional Azure resource tags."
  type        = map(string)
  default     = {}
}

variable "subscription_id" {
  description = "Optional Azure subscription ID; defaults to AzureRM environment/CLI authentication."
  type        = string
  default     = null
}
