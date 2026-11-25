# ---------------------------------------------------------------------------
# Variables the DBA team is expected to own per instance.
# Everything else is decided once, for everyone, in this module.
# ---------------------------------------------------------------------------

variable "name" {
  description = "Base name for the Cloud SQL instance and its resources."
  type        = string
}

variable "project_id" {
  description = "GCP project that hosts the Cloud SQL instance."
  type        = string
}

variable "environment" {
  description = "Deployment environment. Must be one of apps-dev, apps-staging, apps-prod."
  type        = string

  validation {
    condition     = contains(["apps-dev", "apps-staging", "apps-prod"], var.environment)
    error_message = "environment must be one of apps-dev, apps-staging or apps-prod."
  }
}

variable "region" {
  description = "GCP region for the Cloud SQL instance."
  type        = string
}

variable "database_version" {
  description = "PostgreSQL version, e.g. POSTGRES_15."
  type        = string
  default     = "POSTGRES_15"
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680."
  type        = string
}

variable "disk_size_gb" {
  description = "Provisioned storage size in GB."
  type        = number
  default     = 10
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum size to which storage may auto-grow. 0 disables auto-resize."
  type        = number
  default     = 0
}

variable "availability_type" {
  description = "Availability type: ZONAL or REGIONAL. REGIONAL provides high availability."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from accidental deletion."
  type        = bool
  default     = true
}

variable "backup_enabled" {
  description = "Enable automated backups."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Daily backup window start (HH:MM) in UTC."
  type        = string
  default     = "03:00"
}

variable "retained_backups" {
  description = "Number of automated backups to retain (1-365)."
  type        = number
  default     = 7
}

variable "transaction_log_retention_days" {
  description = "Days to retain PostgreSQL transaction logs (1-7). 0 disables PITR."
  type        = number
  default     = 7
}

variable "point_in_time_recovery_enabled" {
  description = "Enable point-in-time recovery."
  type        = bool
  default     = true
}

variable "maintenance_window_day" {
  description = "Day of week (1-7, Monday=1) for maintenance."
  type        = number
  default     = 7
}

variable "maintenance_window_hour" {
  description = "Hour of day (0-23) for maintenance."
  type        = number
  default     = 4
}

variable "ipv4_enabled" {
  description = "Enable a public IPv4 address. Defaults to false for private-only networking."
  type        = bool
  default     = false
}

variable "require_ssl" {
  description = "Require trusted client certificates on the public path. Private path traffic is VPC-only."
  type        = bool
  default     = true
}

variable "user_labels" {
  description = "Additional labels to apply to the instance."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Private network attachment. The network team owns the VPC and has already
# configured private services access on each.
# ---------------------------------------------------------------------------

variable "network" {
  description = "VPC network to attach the instance to (self link or name)."
  type        = string
}

variable "private_ip_allocated_range" {
  description = "Name of the allocated IP range for private services access (optional)."
  type        = string
  default     = null
}