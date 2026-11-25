variable "project_number" {
  description = "Numeric project number for project_id. Supplying it explicitly avoids a privileged, plan-time project lookup and is used to identify the Google-managed GKE service agent."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{6,20}$", var.project_number))
    error_message = "project_number must contain only the 6-20 digit numeric Google Cloud project number, not the project ID."
  }
}
