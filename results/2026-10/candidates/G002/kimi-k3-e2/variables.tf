# ---------------------------------------------------------------------------
# Required inputs — decisions that belong to the DBA team for every instance.
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "ID of the GCP project the instance lives in."
  type        = string
  nullable    = false
}

variable "region" {
  description = "Region of the instance (e.g. \"europe-west1\")."
  type        = string
  nullable    = false
}

variable "name" {
  description = "Instance name. Lowercase letters, digits and hyphens; must start with a letter."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}$", var.name))
    error_message = "name must be 1-62 characters: lowercase letters, digits, hyphens, starting with a letter."
  }
}

variable "network" {
  description = <<-EOT
    Name of the VPC network the instance is attached to with a private IP —
    one of the environment networks managed by the network team
    (e.g. "apps-dev", "apps-staging", "apps-prod"). Private services access
    must already be configured on the network (the network team has done this).
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}$", var.network))
    error_message = "network must be a VPC network name (lowercase letters, digits, hyphens), not a self-link."
  }
}

variable "network_project_id" {
  description = "Project owning the VPC network. Defaults to var.project_id; set this when the networks live in a Shared VPC host project."
  type        = string
  default     = null
}

variable "tier" {
  description = "Machine series/tier, e.g. \"db-custom-4-16384\" (ENTERPRISE) or \"db-perf-optimized-N-M\" (ENTERPRISE_PLUS)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(db-f1-micro|db-g1-small|db-custom-[0-9]+-[0-9]+|db-perf-optimized-[0-9]+-[0-9]+)$", var.tier))
    error_message = "tier must be a Cloud SQL machine type: db-custom-N-MEM, db-perf-optimized-N-MEM, db-f1-micro or db-g1-small."
  }
}

# ---------------------------------------------------------------------------
# Sizing and version
# ---------------------------------------------------------------------------

variable "database_version" {
  description = "PostgreSQL version (this module is PostgreSQL-only by design)."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+(_[0-9]+)?$", var.database_version))
    error_message = "database_version must look like \"POSTGRES_16\"."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS (ENTERPRISE_PLUS requires a db-perf-optimized-* tier)."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "ZONAL (single zone) or REGIONAL (HA with a standby in another zone)."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size" {
  description = "Initial data disk size in GB. Autoresize is on by default, so this is the floor, not the ceiling."
  type        = number
  default     = 10
}

variable "disk_type" {
  description = "PD_SSD, PD_HDD or HYPERDISK_BALANCED (HYPERDISK_BALANCED requires ENTERPRISE_PLUS)."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be PD_SSD, PD_HDD or HYPERDISK_BALANCED."
  }
}

variable "disk_autoresize" {
  description = "Grow the disk automatically rather than running out of space."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "Cap in GB for autoresize growth. 0 = no cap."
  type        = number
  default     = 0
}

# ---------------------------------------------------------------------------
# Operability — backup, maintenance, observability
# ---------------------------------------------------------------------------

variable "backup" {
  description = "Automated backup policy. start_time is UTC HH:MM. PITR is on by default."
  type = object({
    enabled                        = optional(bool, true)
    start_time                     = optional(string, "02:00")
    point_in_time_recovery_enabled = optional(bool, true)
    transaction_log_retention_days = optional(number, 7)
    retained_backups               = optional(number, 7)
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup.start_time))
    error_message = "backup.start_time must be HH:MM (UTC, 24h)."
  }
  validation {
    condition     = var.backup.retained_backups >= 1 && var.backup.retained_backups <= 365
    error_message = "backup.retained_backups must be between 1 and 365."
  }
  validation {
    condition     = var.backup.transaction_log_retention_days >= 1 && var.backup.transaction_log_retention_days <= 7
    error_message = "backup.transaction_log_retention_days must be between 1 and 7."
  }
}

variable "maintenance_window" {
  description = "Maintenance window: day 1-7 (1 = Monday, 7 = Sunday), hour 0-23 UTC. Defaults to Sunday 03:00, stable track."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string, "stable")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7
    error_message = "maintenance_window.day must be 1-7 (1 = Monday, 7 = Sunday)."
  }
  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.hour must be 0-23."
  }
  validation {
    condition     = contains(["stable", "canary", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be stable, canary or week5."
  }
}

variable "query_insights" {
  description = "Query Insights knobs. Query Insights itself is always enabled — that is the standard."
  type = object({
    query_string_length     = optional(number, 1024)
    record_application_tags = optional(bool, true)
    record_client_address   = optional(bool, true)
    query_plans_per_minute  = optional(number, 5)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.query_insights.query_string_length >= 256 && var.query_insights.query_string_length <= 4500
    error_message = "query_insights.query_string_length must be between 256 and 4500."
  }
  validation {
    condition     = var.query_insights.query_plans_per_minute >= 0 && var.query_insights.query_plans_per_minute <= 200
    error_message = "query_insights.query_plans_per_minute must be between 0 and 200."
  }
}

# ---------------------------------------------------------------------------
# Security-adjacent knobs that remain DBA decisions
# ---------------------------------------------------------------------------

variable "database_flags" {
  description = <<-EOT
    PostgreSQL flags to set (e.g. { max_connections = "500", log_min_duration_statement = "250" }).
    The module always enforces cloudsql.iam_authentication = "on"; that flag is
    merged last and cannot be overridden here.
  EOT
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "ssl_mode" {
  description = "How clients may connect. ENCRYPTED_ONLY is the standard; relax only with a documented reason."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ALLOW_UNENCRYPTED_AND_ENCRYPTED", "ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be ALLOW_UNENCRYPTED_AND_ENCRYPTED, ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}

variable "password_validation_policy" {
  description = "Optional password policy for any built-in (non-IAM) Postgres roles. Null = no policy block."
  type = object({
    min_length                  = optional(number, 12)
    complexity                  = optional(string, "COMPLEXITY_DEFAULT")
    reuse_interval              = optional(number, 60)
    disallow_username_substring = optional(bool, true)
    password_change_interval    = optional(string, null)
  })
  default = null

  validation {
    condition     = var.password_validation_policy == null || contains(["COMPLEXITY_DEFAULT", "COMPLEXITY_UNSPECIFIED"], var.password_validation_policy.complexity)
    error_message = "password_validation_policy.complexity must be COMPLEXITY_DEFAULT or COMPLEXITY_UNSPECIFIED."
  }
}

variable "encryption_key_name" {
  description = "Optional CMEK — full KMS key resource ID. Null = Google-managed encryption at rest."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Protect the instance from deletion. Keep this true everywhere except genuinely throwaway instances."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Schema and access
# ---------------------------------------------------------------------------

variable "databases" {
  description = "Databases to create, keyed by database name. Charset/collation default to the server defaults."
  type = map(object({
    charset   = optional(string, null)
    collation = optional(string, null)
  }))
  default  = {}
  nullable = false
}

variable "iam_users" {
  description = <<-EOT
    IAM identities to create as database users, keyed by a stable label.
    email = user / group / service-account email; type = CLOUD_IAM_USER
    (default), CLOUD_IAM_GROUP or CLOUD_IAM_SERVICE_ACCOUNT. For service
    accounts the ".gserviceaccount.com" suffix is trimmed automatically, as
    Cloud SQL requires. Humans log in as themselves (or via their group) —
    that is what the security team audits.
  EOT
  type = map(object({
    email = string
    type  = optional(string, "CLOUD_IAM_USER")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for u in var.iam_users : contains(["CLOUD_IAM_USER", "CLOUD_IAM_GROUP", "CLOUD_IAM_SERVICE_ACCOUNT"], u.type)])
    error_message = "iam_users type must be CLOUD_IAM_USER, CLOUD_IAM_GROUP or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}

variable "labels" {
  description = "Labels applied to the instance (e.g. environment, team, cost-center)."
  type        = map(string)
  default     = {}
  nullable    = false
}
