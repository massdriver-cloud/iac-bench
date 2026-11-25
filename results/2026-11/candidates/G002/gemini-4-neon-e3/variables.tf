# ------------------------------------------------------------------------------
# Core Identity & Placement
# ------------------------------------------------------------------------------

variable "name" {
  description = "Cloud SQL PostgreSQL instance name. Must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a lowercase letter or number."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,78}[a-z0-9]$", var.name))
    error_message = "Instance name must be 2-80 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Target deployment environment (dev, staging, or prod). Selects the pre-existing VPC network (apps-<environment>) and sets environment-appropriate defaults for HA, deletion protection, backup retention, and maintenance update track."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "GCP region for the primary Cloud SQL instance. Defaults to the region configured on the Google provider."
  type        = string
  default     = null
}

variable "zone" {
  description = "Preferred primary compute zone (for example, us-central1-a). If omitted, Cloud SQL selects a zone automatically."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Preferred failover zone when availability_type is REGIONAL (for example, us-central1-b). If omitted, Cloud SQL selects a zone automatically."
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# PostgreSQL Engine, Compute & Edition
# ------------------------------------------------------------------------------

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version (for example, POSTGRES_14, POSTGRES_15, POSTGRES_16, POSTGRES_17)."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_(1[4-9]|[2-9][0-9])$", var.database_version))
    error_message = "database_version must be a supported PostgreSQL major version (POSTGRES_14 or newer)."
  }
}

variable "edition" {
  description = "Cloud SQL edition (ENTERPRISE or ENTERPRISE_PLUS)."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be either ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier (for example, db-custom-2-8192 for ENTERPRISE or db-perf-optimized-N-2 for ENTERPRISE_PLUS)."
  type        = string
  default     = "db-custom-2-8192"

  validation {
    condition     = can(regex("^db-[a-zA-Z0-9-]+$", var.tier))
    error_message = "tier must be a valid Cloud SQL machine tier starting with 'db-' (for example, db-custom-2-8192 or db-perf-optimized-N-2)."
  }
}

variable "data_cache_enabled" {
  description = "Enable Cloud SQL data cache (only supported with edition = ENTERPRISE_PLUS)."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# High Availability & Deletion Protection
# ------------------------------------------------------------------------------

variable "availability_type" {
  description = "Instance availability type (REGIONAL for HA or ZONAL). Defaults to REGIONAL in prod and ZONAL in dev and staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL, ZONAL, or null."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from accidental deletion in both OpenTofu and the Cloud SQL API. Defaults to true in prod and false in dev and staging."
  type        = bool
  default     = null
}

# ------------------------------------------------------------------------------
# Storage (SSD + Autoresize Always Enabled)
# ------------------------------------------------------------------------------

variable "disk_type" {
  description = "Storage disk type (PD_SSD or HYPERDISK_BALANCED). Spinning HDD is disallowed."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be PD_SSD or HYPERDISK_BALANCED."
  }
}

variable "disk_size_gb" {
  description = "Initial storage size in GB. Because disk_autoresize is always enabled, subsequent disk growth is managed automatically by Cloud SQL and ignored in drift detection."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be an integer of at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper cap in GB for automatic storage increase (0 means unlimited)."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0 && floor(var.disk_autoresize_limit_gb) == var.disk_autoresize_limit_gb
    error_message = "disk_autoresize_limit_gb must be a non-negative integer."
  }
}

# ------------------------------------------------------------------------------
# Backups & Point-in-Time Recovery (Always Enabled)
# ------------------------------------------------------------------------------

variable "backup_start_time" {
  description = "Start time (HH:MM in UTC) for the daily 4-hour automated backup window."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be in 24-hour HH:MM UTC format (for example, 03:00)."
  }
}

variable "backup_location" {
  description = "Multi-region or region where automated backups are stored (for example, us or eu). Defaults to Cloud SQL's default location for the instance region."
  type        = string
  default     = null
}

variable "retained_backups" {
  description = "Number of daily automated backups to retain. Defaults to 30 in prod, 14 in staging, and 7 in dev."
  type        = number
  default     = null

  validation {
    condition     = var.retained_backups == null || (var.retained_backups >= 7 && var.retained_backups <= 365 && floor(var.retained_backups) == var.retained_backups)
    error_message = "retained_backups must be an integer between 7 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of transaction logs retained for point-in-time recovery. Defaults to 7 in prod and staging, and 3 in dev. Max is 7 for ENTERPRISE and 35 for ENTERPRISE_PLUS."
  type        = number
  default     = null

  validation {
    condition     = var.transaction_log_retention_days == null || (var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35 && floor(var.transaction_log_retention_days) == var.transaction_log_retention_days)
    error_message = "transaction_log_retention_days must be an integer between 1 and 35."
  }
}

# ------------------------------------------------------------------------------
# Maintenance Window & Freeze Periods
# ------------------------------------------------------------------------------

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC. update_track defaults to canary in dev and stable in staging and prod."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 4)
    update_track = optional(string)
  })
  default = {}

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day
    error_message = "maintenance_window.day must be an integer from 1 (Monday) to 7 (Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour
    error_message = "maintenance_window.hour must be an integer from 0 to 23 (UTC)."
  }

  validation {
    condition     = var.maintenance_window.update_track == null || contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be canary, stable, week5, or null."
  }
}

variable "deny_maintenance_period" {
  description = "Optional maintenance freeze period (for example, peak retail or quarter-end windows)."
  type = object({
    start_date = string
    end_date   = string
    time       = optional(string, "00:00:00")
  })
  default = null

  validation {
    condition = var.deny_maintenance_period == null || (
      can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.deny_maintenance_period.start_date)) &&
      can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.deny_maintenance_period.end_date)) &&
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$", var.deny_maintenance_period.time))
    )
    error_message = "deny_maintenance_period dates must be YYYY-MM-DD and time must be HH:MM:SS."
  }
}

# ------------------------------------------------------------------------------
# PostgreSQL Flags & Query Insights
# ------------------------------------------------------------------------------

variable "database_flags" {
  description = "PostgreSQL database flags owned by the DBA team (for example, max_connections, work_mem, log_min_duration_statement, pgaudit.log). Mandatory security and audit flags (cloudsql.iam_authentication, cloudsql.enable_pgaudit, log_connections, log_disconnections) are enforced by this module and cannot be overridden."
  type        = map(string)
  default     = {}

  validation {
    condition = length(setintersection(
      keys(var.database_flags),
      ["cloudsql.iam_authentication", "cloudsql.enable_pgaudit", "log_connections", "log_disconnections"]
    )) == 0
    error_message = "Mandatory security and audit flags (cloudsql.iam_authentication, cloudsql.enable_pgaudit, log_connections, log_disconnections) are standardized by this module and cannot be overridden."
  }

  validation {
    condition     = lower(lookup(var.database_flags, "pgaudit.log", "ddl,role")) != "none"
    error_message = "pgaudit.log cannot be set to 'none'; audit logging must remain enabled."
  }
}

variable "query_insights" {
  description = "Query Insights tuning parameters. Query Insights is always enabled across all instances."
  type = object({
    query_string_length     = optional(number, 1024)
    query_plans_per_minute  = optional(number, 5)
    record_application_tags = optional(bool, true)
    record_client_address   = optional(bool, true)
  })
  default = {}

  validation {
    condition     = var.query_insights.query_string_length >= 256 && var.query_insights.query_string_length <= 4500
    error_message = "query_insights.query_string_length must be between 256 and 4500."
  }

  validation {
    condition     = var.query_insights.query_plans_per_minute >= 0 && var.query_insights.query_plans_per_minute <= 20
    error_message = "query_insights.query_plans_per_minute must be between 0 and 20."
  }
}

# ------------------------------------------------------------------------------
# Networking & Security Controls
# ------------------------------------------------------------------------------

variable "allocated_ip_range" {
  description = "Optional name of a specific private services access IP range in the environment VPC. Leave null to let Cloud SQL select the VPC's allocated PSA range automatically."
  type        = string
  default     = null
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS CryptoKey resource ID for customer-managed encryption keys (CMEK) at rest. If omitted, Google-managed encryption is used."
  type        = string
  default     = null
}

variable "connector_enforcement" {
  description = "Whether to require connections via Cloud SQL Auth Proxy or Language Connectors (NOT_REQUIRED or REQUIRED). TLS is always enforced regardless of this setting."
  type        = string
  default     = "NOT_REQUIRED"

  validation {
    condition     = contains(["NOT_REQUIRED", "REQUIRED"], var.connector_enforcement)
    error_message = "connector_enforcement must be NOT_REQUIRED or REQUIRED."
  }
}

# ------------------------------------------------------------------------------
# Databases & Google Identity Access (IAM Auth Only)
# ------------------------------------------------------------------------------

variable "databases" {
  description = "Map of PostgreSQL databases to create on this instance, keyed by database name."
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string, "en_US.UTF8")
    deletion_policy = optional(string, "DELETE")
  }))
  default = {}

  validation {
    condition     = alltrue([for _, db in var.databases : contains(["DELETE", "ABANDON"], db.deletion_policy)])
    error_message = "Each database deletion_policy must be either DELETE or ABANDON."
  }
}

variable "iam_users" {
  description = "Set of Google user email addresses (engineers and DBAs) granted CLOUD_IAM_USER access to this instance."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", u)) && !endswith(u, ".gserviceaccount.com")])
    error_message = "Each entry in iam_users must be a user email address (put service accounts in iam_service_accounts)."
  }
}

variable "iam_service_accounts" {
  description = "Set of Google service account email addresses (GKE/Compute Engine workloads) granted CLOUD_IAM_SERVICE_ACCOUNT access. The .gserviceaccount.com suffix is stripped automatically as required by Cloud SQL for PostgreSQL."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : endswith(sa, ".gserviceaccount.com") && can(regex("^[^@\\s]+@[^@\\s]+\\.gserviceaccount\\.com$", sa))])
    error_message = "Each entry in iam_service_accounts must be a full Google service account email ending in .gserviceaccount.com."
  }
}

variable "iam_groups" {
  description = "Set of Google Group email addresses granted CLOUD_IAM_GROUP access to this instance."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for g in var.iam_groups : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", g)) && !endswith(g, ".gserviceaccount.com")])
    error_message = "Each entry in iam_groups must be a valid Google Group email address."
  }
}

variable "grant_project_iam_roles" {
  description = "When true, also grants project-level roles/cloudsql.instanceUser and roles/cloudsql.client to the configured iam_users, iam_service_accounts, and iam_groups. Defaults to false because Cloud SQL IAM roles are project-scoped and shared across instances in the same project."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# Read Replicas (Optional)
# ------------------------------------------------------------------------------

variable "read_replicas" {
  description = "Optional map of read replicas keyed by suffix (replica instance name becomes <name>-<key>). Replicas inherit private networking, TLS, IAM authentication, audit logging, and Query Insights standards."
  type = map(object({
    tier                     = optional(string)
    region                   = optional(string)
    zone                     = optional(string)
    availability_type        = optional(string, "ZONAL")
    disk_type                = optional(string)
    disk_autoresize_limit_gb = optional(number)
    database_flags           = optional(map(string), {})
    encryption_key_name      = optional(string)
    deletion_protection      = optional(bool)
    labels                   = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, _ in var.read_replicas : can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", k))])
    error_message = "Read replica keys must be 1-16 lowercase alphanumeric/hyphen characters."
  }

  validation {
    condition     = alltrue([for _, r in var.read_replicas : r.tier == null || can(regex("^db-[a-zA-Z0-9-]+$", r.tier))])
    error_message = "Each read replica tier must be a valid Cloud SQL machine tier starting with 'db-'."
  }

  validation {
    condition     = alltrue([for _, r in var.read_replicas : contains(["ZONAL", "REGIONAL"], r.availability_type)])
    error_message = "Each read replica availability_type must be ZONAL or REGIONAL."
  }

  validation {
    condition     = alltrue([for _, r in var.read_replicas : r.disk_type == null || contains(["PD_SSD", "HYPERDISK_BALANCED"], r.disk_type)])
    error_message = "Each read replica disk_type must be PD_SSD or HYPERDISK_BALANCED."
  }

  validation {
    condition     = alltrue([for _, r in var.read_replicas : r.disk_autoresize_limit_gb == null || (r.disk_autoresize_limit_gb >= 0 && floor(r.disk_autoresize_limit_gb) == r.disk_autoresize_limit_gb)])
    error_message = "Each read replica disk_autoresize_limit_gb must be a non-negative integer."
  }

  validation {
    condition = alltrue([
      for _, r in var.read_replicas : length(setintersection(
        keys(r.database_flags),
        ["cloudsql.iam_authentication", "cloudsql.enable_pgaudit", "log_connections", "log_disconnections"]
      )) == 0
    ])
    error_message = "Read replica database_flags cannot override mandatory security and audit flags (cloudsql.iam_authentication, cloudsql.enable_pgaudit, log_connections, log_disconnections)."
  }

  validation {
    condition     = alltrue([for _, r in var.read_replicas : lower(lookup(r.database_flags, "pgaudit.log", "ddl,role")) != "none"])
    error_message = "Read replica pgaudit.log cannot be set to 'none'; audit logging must remain enabled."
  }
}

# ------------------------------------------------------------------------------
# Labels
# ------------------------------------------------------------------------------

variable "labels" {
  description = "Additional GCP resource labels (for example, team, application, cost-center) merged with the module's standardized labels."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys must start with a lowercase letter and keys/values may contain only lowercase letters, digits, underscores, and hyphens (max 63 chars)."
  }
}
