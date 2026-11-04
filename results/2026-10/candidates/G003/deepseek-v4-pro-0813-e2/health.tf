variable "health_check_path" {
  description = "Path to the liveness/health endpoint for the platform to probe."
  type        = string
  default     = "/healthz"
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes of failed health probes before an instance is evicted."
  type        = number
  default     = 10
}