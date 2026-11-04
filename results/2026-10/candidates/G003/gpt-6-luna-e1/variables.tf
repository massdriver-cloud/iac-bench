variable "resource_group_name" {
  description = "Name of the resource group created for this service and its observability resources."
  type        = string
}

variable "location" {
  description = "Azure region for the service, plan, and monitoring resources."
  type        = string
}

variable "service_name" {
  description = "Globally unique, lowercase App Service name; also used as the suffix for related resource names."
  type        = string

  validation {
    condition     = length(var.service_name) >= 2 && length(var.service_name) <= 40 && can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.service_name))
    error_message = "service_name must be 2-40 characters, start and end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "container_image" {
  description = "Container image and tag (for example, my-api:2025.01)."
  type        = string
  default     = "nginx:1.27-alpine"
}

variable "container_registry_url" {
  description = "Docker registry URL for the image. Use https://index.docker.io for Docker Hub."
  type        = string
  default     = "https://index.docker.io"
}

variable "container_registry_username" {
  description = "Optional username for a private container registry. Supply with container_registry_password."
  type        = string
  default     = null
}

variable "container_registry_password" {
  description = "Optional private registry password. Stored as a sensitive App Service setting."
  type        = string
  sensitive   = true
  default     = null
}

variable "container_port" {
  description = "Port on which the container listens; exposed to the container through WEBSITES_PORT."
  type        = number
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be an integer from 1 through 65535."
  }
}

variable "container_startup_command" {
  description = "Optional command passed to the container at startup."
  type        = string
  default     = null
}

variable "service_plan_sku" {
  description = "Linux App Service plan SKU. Use a production-capable dedicated SKU (for example P1v3)."
  type        = string
  default     = "P1v3"
}

variable "instance_count" {
  description = "Fixed number of workers in the App Service plan. Two workers are used by default for availability."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && floor(var.instance_count) == var.instance_count
    error_message = "instance_count must be a positive integer."
  }
}

variable "health_check_path" {
  description = "HTTP path App Service probes to determine instance health."
  type        = string
  default     = "/"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must begin with '/'."
  }
}

variable "create_staging_slot" {
  description = "Create a staging deployment slot for validation and controlled slot swaps."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Whether the app accepts public inbound traffic. Disable when access is provided through private networking."
  type        = bool
  default     = true
}

variable "integration_subnet_id" {
  description = "Optional delegated subnet ID for outbound regional VNet integration."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Additional application settings. Module-managed container and Application Insights settings take precedence."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "log_retention_days" {
  description = "Retention in days for the Log Analytics workspace and Application Insights."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "log_retention_days must be an integer between 30 and 730."
  }
}

variable "tags" {
  description = "Tags applied to all supported resources."
  type        = map(string)
  default     = {}
}
