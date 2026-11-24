# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Project that hosts the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the Cloud SQL instance (e.g. europe-west1)."
  type        = string
}

variable "environment" {
  description = "Environment the instance serves. Selects the attached VPC (apps-<environment>) and environment-specific defaults (HA, maintenance track)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "name" {
  description = "Cloud SQL instance name. Lowercase letters, digits and hyphens; must start with a letter. Note: Cloud SQL instance names cannot be reused for about a week after deletion."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,78}[a-z0-9]$", var.name))
    error_message = "name must be 2-80 chars, lowercase letters/digits/hyphens, start with a letter and not end with a hyphen."
  }
}

variable "network_project_id" {
  description = "Project that owns the apps-<environment> VPC network (where private services access is configured). Defaults to project_id."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Optional name of a specific private services access range to allocate the instance IP from. Null lets Cloud SQL pick any range allocated on the network."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# DBA-owned engine and sizing decisions
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
  description = "REGIONAL (HA with standby in another zone) or ZONAL. Null selects REGIONAL for prod and ZONAL otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "availability_type must be REGIONAL, ZONAL or null."
  }
}

variable "zone" {
  description = "Optional preferred primary zone. Null lets Cloud SQL choose."
  type        = string
  default     = null
}

variable "disk_size_gb" {
  description = "Initial SSD disk size in GB. Storage auto-grows; Terraform ignores later drift caused by auto-resize."
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
  description = "Additional PostgreSQL database flags (name => value). Flags the module enforces for security/audit (IAM authentication, pgaudit, connection logging) cannot be overridden here."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "Databases to create on the instance."
  type        = list(string)
  default     = []
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS key (projects/.../cryptoKeys/...) for CMEK. Null uses Google-managed encryption. Cannot be changed after creation."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------

variable "backup_start_time" {
  description = "Daily backup window start (HH:MM, UTC)."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in 24h format."
  }
}

variable "backup_retained_count" {
  description = "Number of daily automated backups to retain."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retained_count >= 7 && var.backup_retained_count <= 365
    error_message = "backup_retained_count must be between 7 and 365."
  }
}

variable "pitr_log_retention_days" {
  description = "Days of WAL retained for point-in-time recovery (1-7 for ENTERPRISE, up to 35 for ENTERPRISE_PLUS)."
  type        = number
  default     = 7

  validation {
    condition     = var.pitr_log_retention_days >= 1 && var.pitr_log_retention_days <= 35
    error_message = "pitr_log_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Maintenance window: day (1=Mon..7=Sun) and hour (0-23 UTC). update_track null selects 'canary' for dev/staging and 'stable' for prod."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string)
  })
  default = {}

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.day must be 1-7 and hour 0-23."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion (both OpenTofu-side and Cloud SQL API-side). Set false only deliberately, before destroying."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Extra labels applied to the instance."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Access by Google identity
# ---------------------------------------------------------------------------

variable "iam_users" {
  description = "Google user accounts (email) that log in to PostgreSQL with IAM database authentication."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@]+@[^@]+$", u)) && !endswith(u, ".gserviceaccount.com")])
    error_message = "iam_users must be user emails; put service accounts in iam_service_accounts."
  }
}

variable "iam_service_accounts" {
  description = "Workload service account emails (…@….iam.gserviceaccount.com) that log in with IAM database authentication."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.iam_service_accounts : endswith(s, ".gserviceaccount.com")])
    error_message = "iam_service_accounts must be service account emails ending in .gserviceaccount.com."
  }
}

variable "iam_groups" {
  description = "Google groups (email) whose members log in with IAM database authentication."
  type        = set(string)
  default     = []
}

variable "grant_connect_roles" {
  description = "Grant roles/cloudsql.client and roles/cloudsql.instanceUser on the project to the listed identities, conditioned to this instance only. Disable if access IAM is managed elsewhere."
  type        = bool
  default     = true
}
