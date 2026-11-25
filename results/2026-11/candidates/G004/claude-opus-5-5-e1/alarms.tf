variable "replication_lag_threshold_ms" {
  description = "Cross-region replication lag (ms) above which an alarm fires; this is the effective RPO budget."
  type        = number
  default     = 5000
}

variable "alarm_actions" {
  description = "SNS topic ARNs per region role to notify on replication lag alarms (topics must live in that region)."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}
