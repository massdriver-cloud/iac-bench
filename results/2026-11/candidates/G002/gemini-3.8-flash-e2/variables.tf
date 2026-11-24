# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "name" {
  description = "The name of the Cloud SQL PostgreSQL instance."
  type        = string
}

variable "network" {
  description = "The VPC network for private IP connectivity (e.g., 'apps-dev', 'apps-staging', 'apps-prod', or a full network self-link/ID)."
  type        = string
}

# -----------------------------------------------------------------------------
# Project and Placement
# -----------------------------------------------------------------------------

variable "project" {
  description = "The Google Cloud project ID. If null, the configured provider project is used."
  type        = string
  default     = null
}

variable "region" {
  description = "The Google Cloud region for the Cloud SQL instance."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The primary zone for the instance (e.g., 'us-central1-a'). If null, Cloud SQL selects automatically."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "The secondary zone for regional high-availability standby (e.g., 'us-central1-b'). If null, Cloud SQL selects automatically."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Compute and Storage Architecture
# -----------------------------------------------------------------------------

variable "database_version" {
  description = "The PostgreSQL database engine version to run."
  type        = string
  default     = "POSTGRES_15"
}

variable "tier" {
  description = "The compute tier / machine type for the database instance."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "The availability type for high availability: 'REGIONAL' (recommended for production) or 'ZONAL'."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be either 'REGIONAL' or 'ZONAL'."
  }
}

variable "disk_size" {
  description = "Initial storage disk size in GB."
  type        = number
  default     = 50

  validation {
    condition     = var.disk_size >= 10
    error_message = "disk_size must be at least 10 GB."
  }
}

variable "disk_type" {
  description = "The storage disk type ('PD_SSD' or 'PD_HDD'). Defaults to SSD for DBA workloads."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be either 'PD_SSD' or 'PD_HDD'."
  }
}

variable "disk_autoresize" {
  description = "Whether to allow Cloud SQL to automatically increase disk storage when running low on space."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "The maximum size in GB to which the disk can automatically grow. 0 means unlimited."
  type        = number
  default     = 0
}

# -----------------------------------------------------------------------------
# Security, Networking & Protection
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Whether deletion protection is enabled to prevent accidental destruction."
  type        = bool
  default     = true
}

variable "ssl_mode" {
  description = "SSL mode configuration for the instance. Enforces encrypted client connections."
  type        = string
  default     = "ENCRYPTED_ONLY"
}

variable "enable_private_path_for_google_cloud_services" {
  description = "Whether to enable private path access for Google Cloud services."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Backups and Point-in-Time Recovery
# -----------------------------------------------------------------------------

variable "backup_enabled" {
  description = "Whether automated daily backups are enabled."
  type        = bool
  default     = true
}

variable "point_in_time_recovery_enabled" {
  description = "Whether point-in-time recovery (WAL archiving) is enabled."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "HH:MM format UTC start time for the 4-hour daily backup window."
  type        = string
  default     = "03:00"
}

variable "transaction_log_retention_days" {
  description = "The number of days of transaction logs to retain for point-in-time recovery (1-7)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7
    error_message = "transaction_log_retention_days must be between 1 and 7 days."
  }
}

variable "retained_backups" {
  description = "Number of automated daily backups to retain."
  type        = number
  default     = 14
}

# -----------------------------------------------------------------------------
# Maintenance Window
# -----------------------------------------------------------------------------

variable "maintenance_window_day" {
  description = "Day of week for maintenance window (1-7, where 1 is Monday and 7 is Sunday)."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "maintenance_window_day must be between 1 and 7."
  }
}

variable "maintenance_window_hour" {
  description = "Hour of day for maintenance window in UTC (0-23)."
  type        = number
  default     = 4

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "maintenance_window_hour must be between 0 and 23."
  }
}

variable "maintenance_window_update_track" {
  description = "Receive updates before general rollout ('canary') or after ('stable')."
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["stable", "canary"], var.maintenance_window_update_track)
    error_message = "maintenance_window_update_track must be 'stable' or 'canary'."
  }
}

# -----------------------------------------------------------------------------
# Observability & Query Insights
# -----------------------------------------------------------------------------

variable "query_insights_enabled" {
  description = "Whether to enable Query Insights for database query performance monitoring."
  type        = bool
  default     = true
}

variable "query_insights_query_string_length" {
  description = "Maximum query length in bytes stored in Query Insights (256-4500)."
  type        = number
  default     = 1024
}

variable "query_insights_record_application_tags" {
  description = "Whether Query Insights records application tags from SQL comments."
  type        = bool
  default     = true
}

variable "query_insights_record_client_address" {
  description = "Whether Query Insights records client IP addresses for security and auditing."
  type        = bool
  default     = true
}

variable "query_insights_query_plans_per_minute" {
  description = "Number of query execution plans sampled per minute (0-20)."
  type        = number
  default     = 5
}

# -----------------------------------------------------------------------------
# Database Configuration, Flags, and Workloads
# -----------------------------------------------------------------------------

variable "database_flags" {
  description = "Custom database flags to tune PostgreSQL. Merged with standard security and audit flags."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "databases" {
  description = "List of PostgreSQL databases to provision. Accepts database names (strings) or objects with name, charset, and collation."
  type        = any
  default     = []
}

variable "iam_users" {
  description = "List of Google user email addresses (engineers) to grant Cloud IAM database authentication."
  type        = list(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "List of Google Cloud service account emails (workloads) to grant Cloud IAM database authentication."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Key-value labels to assign to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}
