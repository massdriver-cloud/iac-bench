variable "app_insights_enabled" {
  description = "Provision an Application Insights instance and wire the app to it."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace id to send diagnostics to."
  type        = string
  default     = null
}