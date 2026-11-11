###############################################################################
# Placement and identity
###############################################################################

variable "name" {
  description = "Cloud SQL instance name. Must be unique within the project: lowercase letters, digits and hyphens, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z](?:[-a-z0-9]{0,61}[a-z0-9])?$", var.name))
    error_message = "Instance names must be 1-63 characters, start with a lowercase letter, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Selects the environment's VPC network for private connectivity: apps-dev, apps-staging or apps-prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: \"dev\", \"staging\", \"prod\"."
  }
}

variable "project_id" {
  description = "GCP project that hosts the instance. Defaults to the provider's project (from credentials / GOOGLE_PROJECT)."
  type        = string
  default     = null
}

variable "network_project_id" {
  description = "Project that owns the environment's VPC network. Defaults to project_id; only needed when databases consume a Shared VPC network owned by another project."
  type        = string
  default     = null
}

variable "region" {
  description = "Region for the instance; put it close to the GKE / Compute Engine workloads that connect to it."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Preferred zone for the primary node (e.g. us-central1-a). Leave unset to let Cloud SQL pick."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "zone must be a zone name like us-central1-a."
  }
}

###############################################################################
# Engine and shape — genuinely per-instance decisions, with sane defaults
###############################################################################

variable "postgresql_version" {
  description = "Major PostgreSQL version, without the POSTGRES_ prefix (e.g. \"16\")."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["12", "13", "14", "15", "16", "17", "18"], var.postgresql_version)
    error_message = "postgresql_version must be a Cloud SQL PostgreSQL major version (12 through 18)."
  }
}

variable "tier" {
  description = "Machine tier (e.g. db-g1-small, db-custom-2-7680, db-perf-optimized-N)."
  type        = string
  default     = "db-g1-small"
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "ZONAL or REGIONAL (high availability with a synchronous standby). Use REGIONAL for production instances."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

###############################################################################
# Storage
###############################################################################

variable "disk_type" {
  description = "Storage type: PD_SSD, PD_HDD or HYPERDISK_BALANCED."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be PD_SSD, PD_HDD or HYPERDISK_BALANCED."
  }
}

variable "disk_size_gb" {
  description = "Initial storage size in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize" {
  description = "Grow storage automatically as usage increases."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic storage growth in GB; 0 means unlimited."
  type        = number
  default     = 0
}

###############################################################################
# Access: identities and databases
###############################################################################

variable "iam_users" {
  description = "Google identities (user or service account emails) allowed to authenticate to the database via IAM database authentication. Each identity gets a Cloud SQL IAM user plus roles/cloudsql.instanceUser on the instance. No password users are ever created."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@[:space:]]+@[^@[:space:]]+$", u))])
    error_message = "iam_users entries must be email-form Google identities (users or service accounts)."
  }
}

variable "databases" {
  description = "Databases to create on the instance at provision time."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.databases : can(regex("^[a-z][a-z0-9_-]{0,62}$", d))])
    error_message = "Database names must start with a lowercase letter and contain only lowercase letters, digits, underscores and hyphens."
  }
}

variable "database_flags" {
  description = "PostgreSQL database flags, as name => value. The module always enforces cloudsql.iam_authentication = on (identity-based access); any conflicting entry supplied here is overridden."
  type        = map(string)
  default     = {}
}

###############################################################################
# Operations: maintenance, backups, lifecycle
###############################################################################

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC). Defaults to Sundays at 03:00 on the stable update track."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    )
    error_message = "maintenance_window.day must be 1-7 (Mon-Sun) and maintenance_window.hour must be 0-23."
  }
}

variable "backup_start_time" {
  description = "Start of the daily automated backup window, UTC, as HH:MM."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a 24h HH:MM time, e.g. \"03:00\"."
  }
}

variable "backup_retention_days" {
  description = "Number of automated backups retained."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "backup_retention_days must be between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of transaction logs retained for point-in-time recovery (1-7)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7
    error_message = "transaction_log_retention_days must be between 1 and 7."
  }
}

variable "allocated_ip_range" {
  description = "Name of the private services access (PSA) range to allocate the instance's IP from. Leave unset to let Cloud SQL pick the range already configured on the environment network."
  type        = string
  default     = null
}

variable "user_labels" {
  description = "Extra labels applied to the instance, merged on top of the module's standard labels (environment, managed-by)."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Prevent the instance from being destroyed via OpenTofu or the API. Defaults to true; set false only for disposable instances."
  type        = bool
  default     = true
}
