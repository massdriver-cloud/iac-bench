# -----------------------------------------------------------------------------
# Health & self-healing
# -----------------------------------------------------------------------------

variable "health_check_path" {
  description = "Path App Service probes to decide an instance is healthy; unhealthy instances are removed from rotation and eventually restarted. The container must serve 2xx here."
  type        = string
  default     = "/"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must be an absolute path starting with '/'."
  }
}

variable "health_check_eviction_time_in_minutes" {
  description = "How long an instance may fail the health check before App Service removes it from the load balancer and restarts it. Default 10 minutes."
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_eviction_time_in_minutes >= 1 && var.health_check_eviction_time_in_minutes <= 20
    error_message = "health_check_eviction_time_in_minutes must be between 1 and 20."
  }
}

variable "auto_heal" {
  description = <<-EOT
    Optional self-healing policy: App Service recycles the process when the app
    returns `status_code_count` responses in `status_code_range`, or serves
    `slow_request_count` requests slower than `slow_request_seconds`, within
    `interval_minutes`. Default null: self-healing is off and reliability is
    handled by health check eviction alone.
  EOT
  type = object({
    status_code_range    = optional(string, "500-599")
    status_code_count    = optional(number, 20)
    slow_request_count   = optional(number, 10)
    slow_request_seconds = optional(number, 60)
    interval_minutes     = optional(number, 5)
  })
  default = null
}
