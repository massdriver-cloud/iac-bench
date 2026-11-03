# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Project that will host the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the instance (e.g. europe-west1)."
  type        = string
}

variable "environment" {
  description = "Environment the instance belongs to. Selects the apps-<environment> VPC for private connectivity and drives environment-sensitive defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "network_project_id" {
  description = "Project that owns the apps-<environment> VPC network. Defaults to project_id (set this when the network lives in a Shared VPC host project)."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Optional name of a specific private services access range to allocate the instance IP from. Null lets Cloud SQL pick any range allocated on the network."
  type        = string
  default     = null
}

variable "name" {
  description = "Instance name. Lowercase letters, digits and hyphens; must start with a letter. Note: Cloud SQL names cannot be reused for about a week after deletion."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,78}[a-z0-9]$", var.name))
    error_message = "name must be 2-80 chars, lowercase letters/digits/hyphens, start with a letter and not end with a hyphen."
  }
}

# ---------------------------------------------------------------------------
# DBA-owned sizing / engine decisions
# ---------------------------------------------------------------------------

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
  description = "Machine tier, e.g. db-custom-2-7680 (ENTERPRISE) or db-perf-optimized-N-2 (ENTERPRISE_PLUS)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "REGIONAL (HA with standby) or ZONAL. Null means REGIONAL for prod and ZONAL otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "availability_type must be REGIONAL, ZONAL or null."
  }
}

variable "zone" {
  description = "Optional preferred primary zone."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Optional preferred standby zone (REGIONAL only)."
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
  description = "Initial disk size in GB. Storage auto-resize is always on, so this only sets the floor; drift from growth is ignored."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for storage auto-resize in GB. 0 means no limit."
  type        = number
  default     = 0
}

variable "database_flags" {
  description = "PostgreSQL flags (name => value) tuned by the DBAs. Flags the module enforces for security/audit (IAM auth, pgaudit, connection logging) cannot be overridden here."
  type        = map(string)
  default     = {}
}

variable "pgaudit_log_classes" {
  description = "Value for pgaudit.log (statement classes to audit)."
  type        = string
  default     = "ddl,role"
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------

variable "maintenance_window" {
  description = "Maintenance window: day 1-7 (Mon-Sun), hour 0-23 UTC, update_track canary|stable|week5."
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
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.day must be 1-7 and hour 0-23."
  }
}

variable "backup_start_time" {
  description = "Daily backup start time (HH:MM, UTC)."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in 24h format."
  }
}

variable "backup_location" {
  description = "Optional location for backups (region or multi-region). Null uses the default multi-region nearest the instance."
  type        = string
  default     = null
}

variable "retained_backups" {
  description = "Number of automated daily backups to keep."
  type        = number
  default     = 14

  validation {
    condition     = var.retained_backups >= 7 && var.retained_backups <= 365
    error_message = "retained_backups must be between 7 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of WAL retained for point-in-time recovery (1-7 ENTERPRISE, 1-35 ENTERPRISE_PLUS)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS key (projects/.../cryptoKeys/...) for CMEK. Must be set at creation; the Cloud SQL service agent needs encrypter/decrypter on it."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional labels. environment, managed-by and instance labels are always applied."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Databases & access (Google identities only)
# ---------------------------------------------------------------------------

variable "databases" {
  description = "Databases to create on the instance."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "iam_users" {
  description = "Human Google accounts (email) to create as IAM-authenticated database users. Each also gets roles/cloudsql.instanceUser in the project so they can log in."
  type        = set(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "Workload service account emails (…@….iam.gserviceaccount.com) to create as IAM-authenticated database users. Each also gets roles/cloudsql.client and roles/cloudsql.instanceUser."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : endswith(sa, ".gserviceaccount.com")])
    error_message = "iam_service_accounts must be service account emails ending in .gserviceaccount.com."
  }
}

variable "iam_groups" {
  description = "Google group emails to create as IAM group database users (members log in with their own identity)."
  type        = set(string)
  default     = []
}

variable "grant_project_iam" {
  description = "Whether the module grants roles/cloudsql.client and roles/cloudsql.instanceUser at project level to the listed identities. Disable if access IAM is managed elsewhere."
  type        = bool
  default     = true
}
