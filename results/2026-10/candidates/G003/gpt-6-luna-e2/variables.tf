variable "service_name" {
  description = "Globally unique, lowercase name used for the App Service and related resources."
  type        = string

  validation {
    condition     = length(var.service_name) >= 2 && length(var.service_name) <= 54 && can(regex("^[a-z0-9-]+$", var.service_name)) && can(regex("^[a-z0-9].*[a-z0-9]$", var.service_name))
    error_message = "service_name must be 2-54 characters, start and end with a lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to create for this service."
  type        = string
}

variable "location" {
  description = "Azure region in which to deploy the service."
  type        = string
}

variable "container_image" {
  description = "Container image name and tag, for example nginx:1.25 or myteam/api:1.4. Public Docker Hub images work without credentials."
  type        = string
}

variable "docker_registry_url" {
  description = "Container registry URL used to pull the image."
  type        = string
  default     = "https://index.docker.io"
}

variable "docker_registry_username" {
  description = "Optional username for a private container registry."
  type        = string
  default     = null
  sensitive   = true
}

variable "docker_registry_password" {
  description = "Optional password or token for a private container registry."
  type        = string
  default     = null
  sensitive   = true
}

variable "app_settings" {
  description = "Additional application settings. Platform-managed settings such as WEBSITES_PORT and Application Insights settings are set by this module and take precedence."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "container_port" {
  description = "Port on which the container listens for HTTP traffic."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be between 1 and 65535."
  }
}

variable "sku_name" {
  description = "App Service plan SKU. Premium v3 is the standard production tier; choose a SKU that supports the required region and features."
  type        = string
  default     = "P1v3"
}

variable "worker_count" {
  description = "Initial and minimum number of App Service plan workers. The default of two provides a redundant baseline."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 30
    error_message = "worker_count must be between 1 and 30."
  }
}

variable "max_worker_count" {
  description = "Autoscale ceiling for App Service plan workers."
  type        = number
  default     = 5

  validation {
    condition     = var.max_worker_count >= var.worker_count && var.max_worker_count <= 30
    error_message = "max_worker_count must be at least worker_count and no more than 30."
  }
}

variable "health_check_path" {
  description = "HTTP path used by App Service to probe application health. Set to null to disable the platform health check."
  type        = string
  default     = "/health"
  nullable    = true
}

variable "tags" {
  description = "Tags applied to the resource group and Azure resources."
  type        = map(string)
  default     = {}
}
