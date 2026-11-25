variable "app_name" {
  type        = string
  description = "Name of the application. Will be used to prefix resources."
}

variable "location" {
  type        = string
  description = "Azure region to deploy into."
}

variable "sku_name" {
  type        = string
  description = "The SKU for the App Service Plan (e.g. P1v2, P1v3)."
  default     = "P1v2"
}

variable "worker_count" {
  type        = number
  description = "The initial and minimum number of workers to allocate for the App Service Plan."
  default     = 2
}

variable "max_worker_count" {
  type        = number
  description = "The maximum number of workers for autoscale."
  default     = 5
}

variable "docker_image_name" {
  type        = string
  description = "The docker image name, e.g. 'nginx:latest'."
}

variable "docker_registry_url" {
  type        = string
  description = "The docker registry URL."
  default     = "https://index.docker.io"
}

variable "health_check_path" {
  type        = string
  description = "The path for the health check."
  default     = "/healthz"
}

variable "app_settings" {
  type        = map(string)
  description = "Additional app settings for the web app."
  default     = {}
}

variable "enable_staging_slot" {
  type        = bool
  description = "Whether to create a staging slot for zero-downtime rollouts."
  default     = true
}
