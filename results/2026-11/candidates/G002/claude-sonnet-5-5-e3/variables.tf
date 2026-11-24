############################################
# Identity / placement (always the DBA's call)
############################################

variable "project_id" {
  description = "Project that will own the Cloud SQL instance."
  type        = string
}

variable "name" {
  description = "Instance name. Cloud SQL reserves a name for up to a week after deletion, so choose carefully."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,80}[a-z0-9]$", var.name))
    error_message = "name must be lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment the instance belongs to. Selects the apps-<environment> VPC the instance is attached to and the default for high availability."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Region for the instance. Should match the region of the private services access range in the environment's VPC."
  type        = string
}

variable "network_project_id" {
  description = "Project hosting the apps-<environment> VPC (e.g. a Shared VPC host project). Defaults to project_id."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Optional name of the private services access range to allocate the instance IP from. Null lets Cloud SQL choose from the ranges already on the network."
  type        = string
  default     = null
}

############################################
# Database engine and sizing (DBA decisions)
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
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS. ENTERPRISE_PLUS requires a db-perf-optimized-* tier."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-8192."
  type        = string
  default     = "db-custom-2-8192"
}

variable "disk_size_gb" {
  description = "Initial disk size in GB. Storage autoresize is always on, so this is a floor."
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

variable "high_availability" {
  description = "Regional (HA) instance. Null means: HA for prod, zonal for dev and staging."
  type        = bool
  default     = null
}

variable "availability_zone" {
  description = "Preferred primary zone. Null lets Cloud SQL choose."
  type        = string
  default     = null
}

variable "database_flags" {
  description = "Additional PostgreSQL flags. The module's mandatory flags (IAM authentication, audit and connection logging) cannot be overridden here."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "Names of logical databases to create on the instance."
  type        = list(string)
  default     = []
}

############################################
# Access (identities only, no passwords)
############################################

variable "iam_users" {
  description = <<-EOT
    Google identities that may log in to the instance. Each becomes an IAM database user and is granted
    roles/cloudsql.instanceUser (and roles/cloudsql.client) on this instance only. Use type USER for people
    (email), SERVICE_ACCOUNT for workloads (service account email) or GROUP for Google groups.
    Grants inside PostgreSQL (GRANT ... TO "user") remain the DBAs' responsibility.
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

variable "manage_iam_bindings" {
  description = "Create the project-level (instance-conditioned) IAM bindings for iam_users. Disable if IAM is managed elsewhere."
  type        = bool
  default     = true
}

############################################
# Operations
############################################

variable "backup_start_time" {
  description = "Daily backup start time, UTC, HH:MM."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM (24h)."
  }
}

variable "retained_backups" {
  description = "Number of automated backups to retain."
  type        = number
  default     = 14

  validation {
    condition     = var.retained_backups >= 1
    error_message = "retained_backups must be at least 1."
  }
}

variable "point_in_time_recovery_days" {
  description = "Days of WAL retained for point-in-time recovery (1-35 on Enterprise, 1-7 supported everywhere)."
  type        = number
  default     = 7

  validation {
    condition     = var.point_in_time_recovery_days >= 1 && var.point_in_time_recovery_days <= 35
    error_message = "point_in_time_recovery_days must be between 1 and 35."
  }
}

variable "maintenance_window_day" {
  description = "Maintenance day, 1 (Monday) to 7 (Sunday)."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "maintenance_window_day must be 1-7."
  }
}

variable "maintenance_window_hour" {
  description = "Maintenance hour of day, UTC, 0-23."
  type        = number
  default     = 4

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "maintenance_window_hour must be 0-23."
  }
}

variable "maintenance_update_track" {
  description = "canary or stable. Use stable for prod."
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["canary", "stable"], var.maintenance_update_track)
    error_message = "maintenance_update_track must be canary or stable."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion (both by OpenTofu and by the Cloud SQL API). Must be set to false and applied before the instance can be destroyed."
  type        = bool
  default     = true
}

variable "kms_key_name" {
  description = "Optional customer-managed encryption key (full resource ID) for the instance. Cannot be changed after creation."
  type        = string
  default     = null
}

variable "labels" {
  description = "Extra user labels. The environment label is always set."
  type        = map(string)
  default     = {}
}
