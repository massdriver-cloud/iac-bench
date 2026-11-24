variable "app_name" {
  type        = string
  description = "Name of the application."
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g., prod, staging, dev)."
}

variable "location" {
  type        = string
  description = "Azure region for resources."
}

variable "sku_name" {
  type        = string
  description = "The SKU for the App Service Plan (e.g. P1v2, P1v3, S1)."
  default     = "P1v3"
}

variable "worker_count" {
  type        = number
  description = "The number of instances/workers for the App Service Plan."
  default     = 1
}

variable "zone_redundancy_enabled" {
  type        = bool
  description = "Should the App Service Plan be zone redundant? (Requires at least 3 workers and specific regions/SKUs)."
  default     = false
}

variable "container_image_name" {
  type        = string
  description = "The container image name and tag (e.g. nginx:latest)."
}

variable "container_registry_url" {
  type        = string
  description = "The container registry URL."
  default     = "https://index.docker.io/v1/"
}

variable "health_check_path" {
  type        = string
  description = "The path for the health check probe (e.g. /health)."
  default     = "/health"
}

variable "app_settings" {
  type        = map(string)
  description = "Environment variables for the application."
  default     = {}
}

variable "enable_staging_slot" {
  type        = bool
  description = "Whether to create a staging deployment slot for blue-green rollouts."
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain logs in Log Analytics."
  default     = 30
}
