variable "maintenance_window" {
  description = "Recurring UTC maintenance window. GKE requires at least 48 hours of availability in every rolling 32 days, in windows of at least four hours. Defaults to daily 09:00-13:00 UTC; emergency upgrades can override this."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-01T09:00:00Z"
    end_time   = "2025-01-01T13:00:00Z"
    recurrence = "FREQ=DAILY"
  }
  validation {
    condition     = can(timecmp(var.maintenance_window.end_time, var.maintenance_window.start_time)) && try(timecmp(var.maintenance_window.end_time, var.maintenance_window.start_time) > 0, false)
    error_message = "Use valid RFC3339 timestamps, with end_time later than start_time."
  }
}
