########################################
# Identity / placement
########################################

variable "project_id" {
  description = "Project that owns the Cloud SQL instance."
  type        = string
}

variable "name" {
  description = "Instance name. Cloud SQL reserves a name for about a week after deletion, so choose carefully."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,80}[a-z0-9])?$", var.name))
    error_message = "name must be lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment the instance serves. Selects the VPC (apps-<environment>) the instance is attached to; there is no way to attach to any other network."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Region of the instance. Must be a region where the environment's VPC has private services access."
  type        = string
}

variable "network_project_id" {
  description = "Project that hosts the apps-<environment> VPC (e.g. a shared VPC host project). Defaults to project_id."
  type        = string
  default     = null
}

variable "labels" {
  description = "Extra user labels for the instance."
  type        = map(string)
  default     = {}
}

########################################
# Sizing and engine (DBA decisions)
########################################

variable "database_version" {
  description = "PostgreSQL major version, e.g. POSTGRES_16."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must look like POSTGRES_16."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS (the latter needs a db-perf-optimized-* tier)."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680 or db-perf-optimized-N-4."
  type        = string
}

variable "disk_size_gb" {
  description = "Initial disk size in GB. Storage auto-grows, and can never be shrunk."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_type" {
  description = "PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "availability_type" {
  description = "ZONAL or REGIONAL (high availability). Null means REGIONAL for staging and prod, ZONAL for dev."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["ZONAL", "REGIONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "availability_type must be ZONAL, REGIONAL or null."
  }
}

variable "zone" {
  description = "Preferred primary zone. Null lets Cloud SQL choose."
  type        = string
  default     = null
}

variable "databases" {
  description = "Databases to create on the instance."
  type        = list(string)
  default     = []
}

variable "database_flags" {
  description = "Additional PostgreSQL flags chosen by the DBAs. Flags the module enforces (IAM authentication, pgaudit, connection logging) cannot be overridden."
  type        = map(string)
  default     = {}
}

variable "log_min_duration_statement_ms" {
  description = "Log statements slower than this many milliseconds. -1 disables, 0 logs everything."
  type        = number
  default     = 1000
}

variable "pgaudit_log" {
  description = "Value of pgaudit.log: the statement classes written to the audit log (comma separated)."
  type        = string
  default     = "ddl,role"
}

########################################
# Operations
########################################

variable "backup_start_time" {
  description = "Daily backup window start, HH:MM in UTC."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM (24h, UTC)."
  }
}

variable "backup_retained_count" {
  description = "Number of automated backups to keep. Null means 7 for dev and 30 for staging and prod."
  type        = number
  default     = null
}

variable "point_in_time_recovery_days" {
  description = "Days of WAL retained for point-in-time recovery (1-35)."
  type        = number
  default     = 7

  validation {
    condition     = var.point_in_time_recovery_days >= 1 && var.point_in_time_recovery_days <= 35
    error_message = "point_in_time_recovery_days must be between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Maintenance window: day 1 (Mon) to 7 (Sun), hour 0-23 UTC, and update track (stable, canary or week5)."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string, "stable")
  })
  default = {
    day  = 7
    hour = 3
  }

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 &&
      contains(["stable", "canary", "week5"], var.maintenance_window.update_track)
    )
    error_message = "maintenance_window needs day 1-7, hour 0-23 and update_track stable, canary or week5."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the instance, both in OpenTofu and in Cloud SQL itself. Turn off deliberately, in a separate apply, before destroying."
  type        = bool
  default     = true
}

########################################
# Access (by Google identity)
########################################

variable "iam_users" {
  description = "Human users (email addresses) who may log in with their Google identity."
  type        = list(string)
  default     = []
}

variable "iam_groups" {
  description = "Google groups (email addresses) whose members may log in with their own identity."
  type        = list(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "Service account emails (workloads on GKE / Compute Engine) that may log in as themselves."
  type        = list(string)
  default     = []
}
