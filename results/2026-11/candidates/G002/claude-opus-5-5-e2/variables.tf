############################################
# Identity / placement
############################################

variable "project_id" {
  description = "Project that hosts the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the Cloud SQL instance (e.g. europe-west1)."
  type        = string
}

variable "name" {
  description = "Cloud SQL instance name. Lowercase letters, digits and hyphens; must start with a letter. Instance names cannot be reused for a week after deletion."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,78}[a-z0-9]$", var.name))
    error_message = "name must be 2-80 chars of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment: dev, staging or prod. Selects the apps-<environment> VPC and environment-appropriate defaults (HA, backup retention)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "network_project_id" {
  description = "Project that owns the apps-<environment> VPC (e.g. a Shared VPC host project). Defaults to project_id."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of a specific private services access range to allocate the instance IP from. Null lets Cloud SQL choose any range allocated on the network."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional user labels for the instance."
  type        = map(string)
  default     = {}
}

############################################
# Engine / sizing (DBA decisions)
############################################

variable "database_version" {
  description = "PostgreSQL major version, e.g. POSTGRES_16."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a PostgreSQL version such as POSTGRES_16."
  }
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

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680 (Enterprise) or db-perf-optimized-N-2 (Enterprise Plus)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "REGIONAL (HA) or ZONAL. Null means REGIONAL in prod and ZONAL elsewhere."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "availability_type must be REGIONAL, ZONAL or null."
  }
}

variable "zone" {
  description = "Preferred primary zone. Null lets Cloud SQL choose."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Preferred standby zone for REGIONAL instances. Null lets Cloud SQL choose."
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
  description = "Initial disk size in GB. With autoresize enabled, the disk grows automatically and this value is ignored after creation."
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
  description = "PostgreSQL database flags (name => value). Merged over the module's logging defaults. cloudsql.iam_authentication is always on and cannot be overridden."
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is enforced by the module and must not be set in database_flags."
  }
}

variable "enable_pgaudit" {
  description = "Enable the pgAudit extension flag (cloudsql.enable_pgaudit) so statement-level audit logs can be configured. The extension still has to be created in each database."
  type        = bool
  default     = false
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS key for CMEK (projects/.../locations/.../keyRings/.../cryptoKeys/...). Null uses Google-managed encryption. Cannot be changed after creation."
  type        = string
  default     = null
}

############################################
# Backups / maintenance
############################################

variable "backup_start_time" {
  description = "Daily backup window start (HH:MM, UTC)."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in 24h format."
  }
}

variable "backup_location" {
  description = "Optional multi-region/region for backup storage. Null uses the default multi-region nearest the instance."
  type        = string
  default     = null
}

variable "retained_backups" {
  description = "Number of automated backups to retain. Null means 30 in prod, 7 elsewhere."
  type        = number
  default     = null

  validation {
    condition     = var.retained_backups == null || (coalesce(var.retained_backups, 7) >= 1 && coalesce(var.retained_backups, 7) <= 365)
    error_message = "retained_backups must be between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of WAL retained for point-in-time recovery (1-7 for Enterprise, up to 35 for Enterprise Plus)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Maintenance window: day (1=Mon..7=Sun), hour (0-23 UTC), update_track (canary, stable or week5)."
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
      contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    )
    error_message = "maintenance_window.day must be 1-7, hour 0-23, update_track canary|stable|week5."
  }
}

variable "deletion_protection" {
  description = "Protect the instance against deletion, both in OpenTofu and at the Cloud SQL API. Set false explicitly (and apply) before destroying."
  type        = bool
  default     = true
}

############################################
# Databases and access
############################################

variable "databases" {
  description = "Databases to create on the instance."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "Google user accounts (emails) that get an IAM database user. Access is via IAM database authentication only; grant privileges inside PostgreSQL."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+$", u)) && !endswith(u, ".gserviceaccount.com")])
    error_message = "iam_users must be user emails; put service accounts in iam_service_accounts."
  }
}

variable "iam_service_accounts" {
  description = "Service account emails (GKE Workload Identity / Compute Engine workloads) that get an IAM database user."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.iam_service_accounts : endswith(s, ".gserviceaccount.com")])
    error_message = "iam_service_accounts must be service account emails ending in .gserviceaccount.com."
  }
}

variable "iam_groups" {
  description = "Google group emails whose members can log in via IAM group authentication."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for g in var.iam_groups : can(regex("^[^@\\s]+@[^@\\s]+$", g))])
    error_message = "iam_groups must be group email addresses."
  }
}

variable "grant_connect_roles" {
  description = "Grant roles/cloudsql.client and roles/cloudsql.instanceUser on the project to every IAM principal above, conditioned to this instance, so they can connect and log in. Disable if access roles are managed elsewhere."
  type        = bool
  default     = true
}
