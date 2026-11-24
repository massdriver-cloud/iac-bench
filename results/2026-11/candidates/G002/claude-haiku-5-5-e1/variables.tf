# ---------------------------------------------------------------------------
# Identity and placement
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project that hosts the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the Cloud SQL instance. Must match the region of the apps-<environment> network's private services access."
  type        = string
}

variable "environment" {
  description = "Environment the instance serves. Selects the application VPC (apps-<environment>) that the instance attaches to."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "network_project_id" {
  description = "Project that owns the apps-<environment> VPC. Defaults to project_id. Set this when networks live in a Shared VPC host project."
  type        = string
  default     = null
}

variable "instance_name" {
  description = "Name of the Cloud SQL instance."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,97}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must be 2-99 chars, lowercase letters, digits and hyphens, starting with a letter and not ending in a hyphen."
  }
}

variable "labels" {
  description = "Additional labels applied to the instance. The module adds environment and managed-by labels."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Engine and sizing (DBA decisions)
# ---------------------------------------------------------------------------

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
  description = "Cloud SQL edition."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "REGIONAL (high availability, standby in another zone) or ZONAL."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL."
  }
}

variable "zone" {
  description = "Preferred zone for the primary. Null lets Cloud SQL choose."
  type        = string
  default     = null
}

variable "disk_size_gb" {
  description = "Initial data disk size in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for disk autoresize in GB. 0 means no limit."
  type        = number
  default     = 0
}

variable "encryption_key_name" {
  description = "Cloud KMS key ID for customer-managed encryption (CMEK). Null uses Google-managed keys."
  type        = string
  default     = null
}

variable "allocated_ip_range_name" {
  description = "Name of the allocated IP range created by the network team for private services access. Null lets Google pick from the connection."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Lifecycle, backup and maintenance
# ---------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Blocks deletion of the instance through the API and console. Turn off only for throwaway instances."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Daily backup window start in HH:MM (UTC)."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in 24-hour format."
  }
}

variable "retained_backups" {
  description = "Number of automated backups to retain."
  type        = number
  default     = 14

  validation {
    condition     = var.retained_backups >= 7 && var.retained_backups <= 365
    error_message = "retained_backups must be between 7 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of write-ahead logs kept for point-in-time recovery."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7
    error_message = "transaction_log_retention_days must be between 1 and 7."
  }
}

variable "maintenance_day" {
  description = "Maintenance window day of week, 1 (Monday) to 7 (Sunday)."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_day >= 1 && var.maintenance_day <= 7
    error_message = "maintenance_day must be between 1 and 7."
  }
}

variable "maintenance_hour" {
  description = "Maintenance window start hour (UTC), 0-23."
  type        = number
  default     = 3

  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23
    error_message = "maintenance_hour must be between 0 and 23."
  }
}

variable "maintenance_update_track" {
  description = "Maintenance update track: stable or canary."
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["stable", "canary"], var.maintenance_update_track)
    error_message = "maintenance_update_track must be stable or canary."
  }
}

# ---------------------------------------------------------------------------
# Databases, flags and access
# ---------------------------------------------------------------------------

variable "database_flags" {
  description = "Additional PostgreSQL flags. Flags the module requires for security and audit (see locals.tf) cannot be overridden here."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "Names of databases to create on the instance."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.databases : can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,62}$", d))])
    error_message = "Each database name must start with a letter and contain only letters, digits, underscores or hyphens."
  }
}

variable "iam_users" {
  description = "Google user account emails (engineers) allowed to authenticate to the database with their IAM identity."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for u in var.iam_users :
      can(regex("^[^@\\s]+@[^@\\s]+$", u)) && !endswith(u, ".gserviceaccount.com")
    ])
    error_message = "iam_users must be user email addresses (not service accounts)."
  }
}

variable "iam_service_accounts" {
  description = "Service account emails (workloads on GKE / Compute Engine) allowed to authenticate with IAM."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.iam_service_accounts : endswith(s, ".gserviceaccount.com")])
    error_message = "iam_service_accounts must be service account emails ending in .gserviceaccount.com."
  }
}
