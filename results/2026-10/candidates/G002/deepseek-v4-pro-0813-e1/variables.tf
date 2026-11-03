# ---------------------------------------------------------------------------
# Identity / location — things every instance must declare.
# ---------------------------------------------------------------------------

variable "name" {
  description = "Base name for the instance. Cloud SQL suffix rules are enforced at the resource."
  type        = string
}

variable "project_id" {
  description = "GCP project in which the instance lives."
  type        = string
}

variable "region" {
  description = "Region for the primary instance."
  type        = string
}

variable "zone" {
  description = "Preferred zone for the primary instance."
  type        = string
  default     = null
}

variable "network_name" {
  description = "VPC network the instance attaches to privately (e.g. apps-dev)."
  type        = string
}

variable "environment" {
  description = "Environment tag (dev, staging, prod). Used for labels and backup policy tuning."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# ---------------------------------------------------------------------------
# Sizing & availability — the DBA's call.
# ---------------------------------------------------------------------------

variable "tier" {
  description = "Machine type for the instance (db-f1-micro, db-custom-*, etc.)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "REGIONAL for HA or ZONAL for single-zone."
  type        = string
  default     = "ZONAL"
}

variable "disk_size_gb" {
  description = "Allocated disk size in GB. Autoresize is always enabled."
  type        = number
  default     = 10
}

variable "disk_type" {
  description = "PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for disk autoresize in GB. 0 disables autoresize."
  type        = number
  default     = 0
}

# ---------------------------------------------------------------------------
# Backups & maintenance — same policy everywhere, DBAs tune the knobs.
# ---------------------------------------------------------------------------

variable "backup_enabled" {
  description = "Enable automated daily backups."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "HH:MM UTC start time for the daily backup window."
  type        = string
  default     = "03:00"
}

variable "backup_retention_count" {
  description = "Number of daily backups to retain."
  type        = number
  default     = 7
}

variable "backup_transaction_log_retention_days" {
  description = "Days of transaction logs retained for PITR."
  type        = number
  default     = 7
}

variable "maintenance_window_day" {
  description = "Preferred maintenance day of week (1 = Monday .. 7 = Sunday)."
  type        = number
  default     = 6
}

variable "maintenance_window_hour" {
  description = "Preferred maintenance hour (0-23)."
  type        = number
  default     = 5
}

variable "deletion_protection" {
  description = "Prevent accidental instance deletion."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Access — always IAM auth + TLS, never public.
# ---------------------------------------------------------------------------

variable "database_name" {
  description = "Name of the application database to create."
  type        = string
}

variable "users" {
  description = "Map of PostgreSQL user -> Google identity (email). Access is audited by these identities."
  type        = map(string)
  default     = {}
}

variable "database_flags" {
  description = "Additional PostgreSQL flags to apply."
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Extra labels to apply to the instance."
  type        = map(string)
  default     = {}
}