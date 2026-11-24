############################################
# Identity / placement
############################################

variable "project_id" {
  description = "Project that will own the Cloud SQL instance."
  type        = string
}

variable "name" {
  description = "Instance name. Cloud SQL reuses names slowly after deletion (up to a week), so choose carefully."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,80}[a-z0-9])?$", var.name))
    error_message = "name must be lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "region" {
  description = "Region of the instance. Must match a region where the environment VPC has private services access."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment. Selects the VPC (apps-<environment>) the instance is attached to and drives environment defaults (HA, update track)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "network_project_id" {
  description = "Project that hosts the apps-<environment> VPC (e.g. a Shared VPC host project). Defaults to project_id."
  type        = string
  default     = null
}

variable "labels" {
  description = "Extra user labels. The module always sets environment and managed_by."
  type        = map(string)
  default     = {}
}

############################################
# DBA decisions: engine, size, availability
############################################

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
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS (the latter requires a db-perf-optimized-N-* tier)."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680. Sizing is the DBA's call, so there is no default."
  type        = string
}

variable "availability_type" {
  description = "REGIONAL (HA) or ZONAL. Null means REGIONAL for prod and ZONAL otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "availability_type must be REGIONAL, ZONAL or null."
  }
}

variable "zone" {
  description = "Preferred primary zone (optional)."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Preferred standby zone for REGIONAL instances (optional)."
  type        = string
  default     = null
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

variable "disk_size_gb" {
  description = "Initial disk size in GB. Storage auto-resizes upward; it can never shrink."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic storage growth in GB. 0 means no limit."
  type        = number
  default     = 0
}

variable "database_flags" {
  description = "Additional PostgreSQL flags (e.g. max_connections, work_mem). Flags the module enforces for auditing/IAM auth cannot be overridden."
  type        = map(string)
  default     = {}
}

variable "pgaudit_log" {
  description = "Value of the pgaudit.log flag (classes of statements to audit)."
  type        = string
  default     = "ddl,role"
}

variable "query_insights_enabled" {
  description = "Enable Query Insights."
  type        = bool
  default     = true
}

############################################
# Backup / maintenance / protection
############################################

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
  description = "Number of automated backups to retain."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retained_count >= 1
    error_message = "backup_retained_count must be at least 1."
  }
}

variable "pitr_log_retention_days" {
  description = "Days of write-ahead logs kept for point-in-time recovery (1-7 for Enterprise, up to 35 for Enterprise Plus)."
  type        = number
  default     = 7

  validation {
    condition     = var.pitr_log_retention_days >= 1 && var.pitr_log_retention_days <= 35
    error_message = "pitr_log_retention_days must be between 1 and 35."
  }
}

variable "backup_location" {
  description = "Multi-region or region to store backups in. Null uses the Cloud SQL default for the instance region."
  type        = string
  default     = null
}

variable "maintenance_window" {
  description = "Maintenance window. day: 1 (Mon) - 7 (Sun); hour: 0-23 UTC. update_track: null means stable for prod and canary otherwise."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string)
  })
  default = {
    day  = 7
    hour = 3
  }

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 &&
      contains(["canary", "stable", "week5"], coalesce(var.maintenance_window.update_track, "stable"))
    )
    error_message = "maintenance_window: day 1-7, hour 0-23, update_track canary|stable|week5."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the instance (both in OpenTofu and in the Cloud SQL API). Turn off and apply before destroying."
  type        = bool
  default     = true
}

variable "kms_key_name" {
  description = "Optional CMEK key (full resource ID) for encryption at rest. Cannot be changed after creation."
  type        = string
  default     = null
}

############################################
# Databases and access
############################################

variable "databases" {
  description = "Databases to create on the instance."
  type        = list(string)
  default     = []
}

variable "iam_users" {
  description = <<-EOT
    Identities allowed to log in with IAM database authentication. This is the only login method the module provisions.
    type: USER (email), SERVICE_ACCOUNT (full service account email) or GROUP (group email).
  EOT
  type = list(object({
    email = string
    type  = optional(string, "USER")
  }))
  default = []

  validation {
    condition     = alltrue([for u in var.iam_users : contains(["USER", "SERVICE_ACCOUNT", "GROUP"], u.type)])
    error_message = "iam_users[*].type must be USER, SERVICE_ACCOUNT or GROUP."
  }
}

variable "grant_connect_roles" {
  description = "Grant roles/cloudsql.client and roles/cloudsql.instanceUser to iam_users, conditioned to this instance only. Disable if IAM is managed elsewhere."
  type        = bool
  default     = true
}
