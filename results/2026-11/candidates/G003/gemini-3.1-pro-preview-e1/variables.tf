variable "app_name" {
  type        = string
  description = "The base name for the application and associated resources."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group to create."
}

variable "location" {
  type        = string
  description = "The Azure region to deploy resources into."
}

variable "sku_name" {
  type        = string
  description = "The App Service Plan SKU (e.g., P1v2, P1v3)."
  default     = "P1v3"
}

variable "worker_count" {
  type        = number
  description = "The number of instances/workers for the App Service Plan."
  default     = 2
}

variable "zone_balancing_enabled" {
  type        = bool
  description = "Enable zone balancing for high availability."
  default     = true
}

variable "container_image" {
  type        = string
  description = "The container image to run (e.g., 'nginx:latest')."
}

variable "container_registry_url" {
  type        = string
  description = "The container registry URL."
  default     = "https://index.docker.io/v1"
}

variable "health_check_path" {
  type        = string
  description = "The HTTP path for App Service health checks."
  default     = "/health"
}

variable "app_settings" {
  type        = map(string)
  description = "A map of application settings (environment variables)."
  default     = {}
}

variable "enable_staging_slot" {
  type        = bool
  description = "Create a staging slot for safe deployments."
  default     = true
}
