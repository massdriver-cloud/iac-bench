# -----------------------------------------------------------------------------
# Required DBA Inputs (Identity, Environment, Sizing)
# -----------------------------------------------------------------------------

variable "name" {
  description = "Logical name of the PostgreSQL workload/instance (e.g. 'orders'). The environment suffix is appended automatically unless already present."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,78}[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a lowercase letter or digit, contain only lowercase letters, digits, or hyphens, and be between 2 and 80 characters."
  }
}

variable "environment" {
  description = "Target deployment environment ('dev', 'staging', or 'prod'). Determines the private VPC network (apps-<environment>) and environment-appropriate HA, backup, and deletion protection defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "tier" {
  description = "Cloud SQL machine type for the primary instance (e.g. 'db-custom-2-8192', 'db-perf-optimized-N-2')."
  type        = string

  validation {
    condition     = length(trimspace(var.tier)) > 0
    error_message = "tier must be a non-empty Cloud SQL machine tier."
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL Engine & Compute Configuration (DBA-Owned)
# -----------------------------------------------------------------------------

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version (e.g. 'POSTGRES_15', 'POSTGRES_16', 'POSTGRES_17')."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a valid Cloud SQL PostgreSQL version such as POSTGRES_15, POSTGRES_16, or POSTGRES_17."
  }
}

variable "edition" {
  description = "Cloud SQL edition ('ENTERPRISE' or 'ENTERPRISE_PLUS')."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be either ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "region" {
  description = "GCP region for the primary instance. Defaults to the region configured on the Google provider."
  type        = string
  default     = null
}

variable "zone" {
  description = "Optional preferred primary zone (e.g. 'us-central1-a')."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Optional preferred secondary zone for REGIONAL high-availability instances."
  type        = string
  default     = null
}

variable "availability_type" {
  description = "High availability mode ('REGIONAL' or 'ZONAL'). When null, defaults to 'REGIONAL' in prod and 'ZONAL' in dev/staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, ""))
    error_message = "availability_type must be null, 'REGIONAL', or 'ZONAL'."
  }
}

# -----------------------------------------------------------------------------
# Storage & Data Protection (DBA-Owned Sizing, Standardized Autoresize & Backups)
# -----------------------------------------------------------------------------

variable "disk_type" {
  description = "Cloud SQL persistent disk type ('PD_SSD', 'PD_BALANCED', or 'HYPERDISK_BALANCED')."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_BALANCED", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be one of: PD_SSD, PD_BALANCED, HYPERDISK_BALANCED."
  }
}

variable "disk_size" {
  description = "Initial storage size in GB. Automatic storage expansion (disk_autoresize) is always enabled."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size >= 10 && floor(var.disk_size) == var.disk_size
    error_message = "disk_size must be an integer >= 10 GB."
  }
}

variable "disk_autoresize_limit" {
  description = "Maximum size in GB to which storage can automatically resize (0 means unlimited)."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit >= 0 && floor(var.disk_autoresize_limit) == var.disk_autoresize_limit
    error_message = "disk_autoresize_limit must be an integer >= 0."
  }
}

variable "deletion_protection" {
  description = "Whether to prevent accidental instance deletion. When null, defaults to true for staging and prod, and false for dev."
  type        = bool
  default     = null
}

variable "kms_key_name" {
  description = "Optional Cloud KMS key resource name for customer-managed encryption keys (CMEK)."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Databases & PostgreSQL Flags (DBA-Owned Tuning + Locked Audit/IAM Standards)
# -----------------------------------------------------------------------------

variable "databases" {
  description = "Map of application PostgreSQL databases to create on the instance, keyed by database name."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "database_flags" {
  description = "Map of DBA-owned PostgreSQL flags (e.g. max_connections, work_mem, shared_buffers, statement_timeout). Mandatory IAM authentication and audit flags are always enforced and cannot be disabled."
  type        = map(string)
  default     = {}
}

variable "pgaudit_log" {
  description = "Comma-separated pgAudit log classes to record (e.g. 'ddl,role', 'write,ddl,role', or 'all'). pgAudit is always enabled for security auditing."
  type        = string
  default     = "ddl,role"

  validation {
    condition     = length(trimspace(var.pgaudit_log)) > 0 && lower(trimspace(var.pgaudit_log)) != "none"
    error_message = "pgaudit_log must be a non-empty pgAudit log setting and cannot be 'none'."
  }
}

# -----------------------------------------------------------------------------
# Google Identity Access & Auditing
# -----------------------------------------------------------------------------

variable "iam_users" {
  description = "Set of Google user email addresses (engineers/DBAs) granted CLOUD_IAM_USER database access and instance-scoped Cloud SQL IAM roles."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", u))])
    error_message = "Each entry in iam_users must be a valid Google user email address."
  }
}

variable "iam_service_accounts" {
  description = "Set of Google service account emails (GKE/GCE workloads) granted CLOUD_IAM_SERVICE_ACCOUNT database access and instance-scoped Cloud SQL IAM roles."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : can(regex("^[^@\\s]+@[^@\\s]+\\.iam(\\.gserviceaccount\\.com)?$|^[^@\\s]+@developer\\.gserviceaccount\\.com$", sa))])
    error_message = "Each entry in iam_service_accounts must be a valid GCP service account email (e.g. 'app@project.iam.gserviceaccount.com')."
  }
}

variable "iam_groups" {
  description = "Set of Google Group email addresses granted CLOUD_IAM_GROUP database access and instance-scoped Cloud SQL IAM roles."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for g in var.iam_groups : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", g))])
    error_message = "Each entry in iam_groups must be a valid Google Group email address."
  }
}

variable "grant_project_iam_roles" {
  description = "When true, grants instance-scoped roles/cloudsql.instanceUser and roles/cloudsql.client to the configured iam_users, iam_service_accounts, and iam_groups."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Backup, Maintenance, Networking & Read Replicas
# -----------------------------------------------------------------------------

variable "backup_start_time" {
  description = "Start time for the daily automated backup window in HH:MM (UTC)."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be in HH:MM 24-hour UTC format."
  }
}

variable "backup_retention_count" {
  description = "Number of daily backups to retain (minimum 7). When null, defaults to 30 for prod, 14 for staging, and 7 for dev."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_count == null || (coalesce(var.backup_retention_count, 7) >= 7 && floor(coalesce(var.backup_retention_count, 7)) == coalesce(var.backup_retention_count, 7))
    error_message = "backup_retention_count must be an integer >= 7."
  }
}

variable "pitr_retention_days" {
  description = "Days of PostgreSQL transaction logs retained for Point-in-Time Recovery (1-7 for ENTERPRISE, 1-35 for ENTERPRISE_PLUS). When null, defaults to 7."
  type        = number
  default     = null

  validation {
    condition     = var.pitr_retention_days == null || (coalesce(var.pitr_retention_days, 7) >= 1 && coalesce(var.pitr_retention_days, 7) <= 35 && floor(coalesce(var.pitr_retention_days, 7)) == coalesce(var.pitr_retention_days, 7))
    error_message = "pitr_retention_days must be an integer between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Maintenance window preferences. Defaults to Sunday at 03:00 UTC on the 'stable' update track."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && contains(["stable", "canary"], var.maintenance_window.update_track)
    error_message = "maintenance_window.day must be 1-7, hour must be 0-23, and update_track must be 'stable' or 'canary'."
  }
}

variable "allocated_ip_range" {
  description = "Optional name of a specific private services access IP range allocation in the environment VPC."
  type        = string
  default     = null
}

variable "read_replicas" {
  description = "Optional map of read replicas to provision for the primary instance, keyed by replica suffix."
  type = map(object({
    tier                  = optional(string)
    region                = optional(string)
    zone                  = optional(string)
    disk_type             = optional(string)
    disk_size             = optional(number)
    disk_autoresize_limit = optional(number)
    availability_type     = optional(string)
    database_flags        = optional(map(string), {})
    deletion_protection   = optional(bool)
    labels                = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.read_replicas :
      can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", k)) &&
      (v.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(v.availability_type, ""))) &&
      (v.disk_type == null || contains(["PD_SSD", "PD_BALANCED", "HYPERDISK_BALANCED"], coalesce(v.disk_type, "")))
    ])
    error_message = "Replica keys must be lowercase alphanumeric/hyphens (1-32 chars), and optional availability_type/disk_type overrides must be valid Cloud SQL values."
  }
}

variable "labels" {
  description = "Additional GCP labels to apply to the primary instance and read replicas."
  type        = map(string)
  default     = {}
}
