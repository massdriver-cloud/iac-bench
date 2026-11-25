################################################################################
# Identity & Environment (Required)
################################################################################

variable "name" {
  description = "Logical name for this PostgreSQL instance (e.g., 'orders', 'billing'). The Cloud SQL instance is named '<name>-<environment>'."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,58}[a-z0-9]$", var.name)) && !can(regex("--", var.name))
    error_message = "name must be 2-60 characters, lowercase alphanumeric with single hyphens, starting with a letter and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Target environment. Determines the private VPC network ('apps-<environment>') and environment-appropriate defaults for HA, backups, maintenance track, and deletion protection."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

################################################################################
# Engine, Compute & Placement (DBA-Owned with Sensible Defaults)
################################################################################

variable "postgres_version" {
  description = "Cloud SQL PostgreSQL major version."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17", "POSTGRES_18"], var.postgres_version)
    error_message = "postgres_version must be a supported Cloud SQL PostgreSQL version (POSTGRES_14 through POSTGRES_18)."
  }
}

variable "edition" {
  description = "Cloud SQL edition: 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier (e.g., 'db-custom-4-16384' for ENTERPRISE or 'db-perf-optimized-N-4' for ENTERPRISE_PLUS). When null, defaults to an environment- and edition-appropriate dedicated tier."
  type        = string
  default     = null

  validation {
    condition     = var.tier == null ? true : !contains(["db-f1-micro", "db-g1-small"], var.tier)
    error_message = "Shared-core tiers (db-f1-micro, db-g1-small) are not permitted; use a dedicated tier."
  }
}

variable "data_cache_enabled" {
  description = "Enable Cloud SQL data cache (only supported with edition = 'ENTERPRISE_PLUS')."
  type        = bool
  default     = false
}

variable "region" {
  description = "GCP region for the primary instance. Defaults to the region configured on the Google provider."
  type        = string
  default     = null
}

variable "zone" {
  description = "Preferred primary GCP zone (e.g., 'us-central1-a'). Leave null to let Cloud SQL choose."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Preferred standby zone when availability_type is 'REGIONAL'. Leave null to let Cloud SQL choose."
  type        = string
  default     = null
}

variable "availability_type" {
  description = "Availability type: 'REGIONAL' (HA) or 'ZONAL'. Defaults to 'REGIONAL' in prod and 'ZONAL' in dev/staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null ? true : contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be 'REGIONAL' or 'ZONAL'."
  }
}

################################################################################
# Storage (DBA-Owned with Auto-Resize Always Enforced)
################################################################################

variable "disk_size_gb" {
  description = "Initial data disk size in GB. Defaults to 20 GB (dev), 50 GB (staging), or 100 GB (prod). Storage auto-resize is always enabled."
  type        = number
  default     = null

  validation {
    condition     = var.disk_size_gb == null ? true : (var.disk_size_gb >= 10 && var.disk_size_gb == floor(var.disk_size_gb))
    error_message = "disk_size_gb must be an integer >= 10."
  }
}

variable "disk_type" {
  description = "Storage disk type: 'PD_SSD' or 'HYPERDISK_BALANCED'."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be 'PD_SSD' or 'HYPERDISK_BALANCED'."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum size in GB to which the disk can automatically grow. Set to 0 for no upper limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0 && var.disk_autoresize_limit_gb == floor(var.disk_autoresize_limit_gb)
    error_message = "disk_autoresize_limit_gb must be an integer >= 0."
  }
}

variable "disk_provisioned_iops" {
  description = "Optional provisioned IOPS when disk_type is 'HYPERDISK_BALANCED'."
  type        = number
  default     = null

  validation {
    condition     = var.disk_provisioned_iops == null ? true : (var.disk_provisioned_iops > 0 && var.disk_provisioned_iops == floor(var.disk_provisioned_iops))
    error_message = "disk_provisioned_iops must be a positive integer."
  }
}

variable "disk_provisioned_throughput" {
  description = "Optional provisioned throughput (MB/s) when disk_type is 'HYPERDISK_BALANCED'."
  type        = number
  default     = null

  validation {
    condition     = var.disk_provisioned_throughput == null ? true : (var.disk_provisioned_throughput > 0 && var.disk_provisioned_throughput == floor(var.disk_provisioned_throughput))
    error_message = "disk_provisioned_throughput must be a positive integer."
  }
}

################################################################################
# PostgreSQL Configuration & Auditing
################################################################################

variable "database_flags" {
  description = "DBA-managed PostgreSQL database flags (e.g., max_connections, work_mem, shared_buffers, autovacuum_*, log_min_duration_statement). Organization-enforced security and auditing flags (cloudsql.iam_authentication, cloudsql.enable_pgaudit, pgaudit.log, pgaudit.log_parameter, log_connections, log_disconnections) cannot be overridden here."
  type        = map(string)
  default     = {}

  validation {
    condition = length(setintersection(
      toset(keys(var.database_flags)),
      toset([
        "cloudsql.iam_authentication",
        "cloudsql.enable_pgaudit",
        "pgaudit.log",
        "pgaudit.log_parameter",
        "log_connections",
        "log_disconnections",
      ])
    )) == 0
    error_message = "Security and audit flags (cloudsql.iam_authentication, cloudsql.enable_pgaudit, pgaudit.log, pgaudit.log_parameter, log_connections, log_disconnections) are enforced by organizational standard. Use var.pgaudit_log to adjust pgAudit statement classes."
  }
}

variable "pgaudit_log" {
  description = "Comma-separated pgAudit log classes (e.g., 'ddl,role', 'write,ddl,role', or 'all'). Must include 'all' or both 'ddl' and 'role'; disabling auditing ('none') is not permitted."
  type        = string
  default     = "ddl,role"

  validation {
    condition = (
      length(trimspace(var.pgaudit_log)) > 0 &&
      alltrue([
        for cls in split(",", var.pgaudit_log) :
        contains(["read", "write", "function", "role", "ddl", "misc", "misc_set", "all"], trimspace(cls))
      ]) &&
      (
        contains([for cls in split(",", var.pgaudit_log) : trimspace(cls)], "all") ||
        (
          contains([for cls in split(",", var.pgaudit_log) : trimspace(cls)], "ddl") &&
          contains([for cls in split(",", var.pgaudit_log) : trimspace(cls)], "role")
        )
      )
    )
    error_message = "pgaudit_log must contain valid pgAudit classes (read, write, function, role, ddl, misc, misc_set, all) and must include either 'all' or both 'ddl' and 'role'."
  }
}

################################################################################
# Logical Databases & IAM Access Control
################################################################################

variable "databases" {
  description = "Map of logical PostgreSQL databases to manage on the primary instance, keyed by database name."
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string, "en_US.UTF8")
    deletion_policy = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, db in var.databases :
      db.deletion_policy == null ? true : contains(["ABANDON", "DELETE"], db.deletion_policy)
    ])
    error_message = "Each database's deletion_policy must be 'ABANDON' or 'DELETE'."
  }
}

variable "iam_users" {
  description = "Set of Google user emails (e.g., 'alice@example.com') granted CLOUD_IAM_USER access to this instance."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", u))])
    error_message = "Every entry in iam_users must be a valid email address."
  }
}

variable "iam_service_accounts" {
  description = "Set of GCP service account emails (e.g., 'orders-api@my-project.iam.gserviceaccount.com') granted CLOUD_IAM_SERVICE_ACCOUNT access. The '.gserviceaccount.com' suffix is stripped automatically for Cloud SQL."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : endswith(sa, ".gserviceaccount.com")])
    error_message = "Every entry in iam_service_accounts must be a full GCP service account email ending in '.gserviceaccount.com'."
  }
}

variable "iam_groups" {
  description = "Set of Google Group emails granted CLOUD_IAM_GROUP access to this instance."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for g in var.iam_groups : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", g))])
    error_message = "Every entry in iam_groups must be a valid Google Group email address."
  }
}

variable "grant_iam_roles" {
  description = "When true, grants conditional roles/cloudsql.instanceUser and roles/cloudsql.client scoped strictly to this instance (and its read replicas) for all principals in iam_users, iam_service_accounts, and iam_groups."
  type        = bool
  default     = true
}

################################################################################
# Backups, Maintenance & Deletion Protection
################################################################################

variable "backup_start_time" {
  description = "UTC start time (HH:MM, 24-hour format) for the daily automated backup window."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be in 24-hour UTC HH:MM format (e.g., '03:00')."
  }
}

variable "backup_retention_count" {
  description = "Number of automated daily backups to retain. Defaults to 7 (dev), 14 (staging), or 30 (prod). Must be >= 7 in staging and prod."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_count == null ? true : (var.backup_retention_count >= 1 && var.backup_retention_count <= 365 && var.backup_retention_count == floor(var.backup_retention_count))
    error_message = "backup_retention_count must be an integer between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Number of days of WAL transaction logs to retain for Point-in-Time Recovery (1-7 for ENTERPRISE, 1-14 for ENTERPRISE_PLUS)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 14 && var.transaction_log_retention_days == floor(var.transaction_log_retention_days)
    error_message = "transaction_log_retention_days must be an integer between 1 and 14."
  }
}

variable "backup_location" {
  description = "Optional multi-region or region for automated backups (e.g., 'us', 'eu'). Leave null to use GCP's regional default."
  type        = string
  default     = null
}

variable "maintenance_window" {
  description = "Weekly maintenance window. Day is 1 (Monday) through 7 (Sunday), hour is 0-23 UTC, update_track defaults to 'canary' in dev and 'stable' in staging/prod."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 4)
    update_track = optional(string, null)
  })
  default = {}

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 &&
      (var.maintenance_window.update_track == null ? true : contains(["canary", "stable", "week5"], var.maintenance_window.update_track))
    )
    error_message = "maintenance_window.day must be 1-7, hour must be 0-23, and update_track must be 'canary', 'stable', or 'week5'."
  }
}

variable "deny_maintenance_period" {
  description = "Optional maintenance freeze period during which Cloud SQL will not perform routine maintenance (dates in YYYY-MM-DD or MM-DD format, time in HH:MM:SS UTC)."
  type = object({
    start_date = string
    end_date   = string
    time       = optional(string, "00:00:00")
  })
  default = null
}

variable "deletion_protection" {
  description = "Protect the instance against accidental deletion at both the OpenTofu and Cloud SQL API layers. Defaults to true in staging and prod, false in dev."
  type        = bool
  default     = null
}

################################################################################
# Read Replicas (DBA-Owned, Inheriting All Security & Networking Standards)
################################################################################

variable "read_replicas" {
  description = "Map of read replicas to create, keyed by a short replica suffix (instance will be named '<name>-<environment>-<key>'). All replicas inherit private-only networking, TLS, IAM auth, pgAudit, and Query Insights."
  type = map(object({
    tier                     = optional(string, null)
    region                   = optional(string, null)
    zone                     = optional(string, null)
    availability_type        = optional(string, "ZONAL")
    disk_type                = optional(string, null)
    disk_autoresize_limit_gb = optional(number, null)
    data_cache_enabled       = optional(bool, null)
    database_flags           = optional(map(string), {})
    allocated_ip_range       = optional(string, null)
    encryption_key_name      = optional(string, null)
    deletion_protection      = optional(bool, null)
    labels                   = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, r in var.read_replicas : (
        can(regex("^[a-z0-9][a-z0-9-]{0,18}[a-z0-9]$", k)) &&
        contains(["ZONAL", "REGIONAL"], r.availability_type) &&
        (r.tier == null ? true : !contains(["db-f1-micro", "db-g1-small"], r.tier)) &&
        (r.disk_type == null ? true : contains(["PD_SSD", "HYPERDISK_BALANCED"], r.disk_type)) &&
        (r.disk_autoresize_limit_gb == null ? true : (r.disk_autoresize_limit_gb >= 0 && r.disk_autoresize_limit_gb == floor(r.disk_autoresize_limit_gb))) &&
        length(setintersection(
          toset(keys(r.database_flags)),
          toset([
            "cloudsql.iam_authentication",
            "cloudsql.enable_pgaudit",
            "pgaudit.log",
            "pgaudit.log_parameter",
            "log_connections",
            "log_disconnections",
          ])
        )) == 0
      )
    ])
    error_message = "Invalid read_replicas configuration: keys must be 2-20 lowercase alphanumeric/hyphen chars, availability_type must be ZONAL or REGIONAL, shared-core tiers are disallowed, and security/audit database flags cannot be overridden."
  }
}

################################################################################
# Networking, Security & Observability Options
################################################################################

variable "allocated_ip_range" {
  description = "Optional name of a specific private services access IP range allocated in the VPC. Leave null to let Cloud SQL select automatically."
  type        = string
  default     = null
}

variable "connector_enforcement" {
  description = "Whether to require connections via Cloud SQL Auth Proxy / Language Connectors ('REQUIRED') or allow direct private-IP TLS + IAM auth connections as well ('NOT_REQUIRED')."
  type        = string
  default     = "NOT_REQUIRED"

  validation {
    condition     = contains(["REQUIRED", "NOT_REQUIRED"], var.connector_enforcement)
    error_message = "connector_enforcement must be 'REQUIRED' or 'NOT_REQUIRED'."
  }
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS key resource ID for Customer-Managed Encryption Keys (CMEK). Leave null to use Google-managed encryption."
  type        = string
  default     = null
}

variable "insights_query_string_length" {
  description = "Maximum SQL query string length (in bytes) recorded by Query Insights (256-4500)."
  type        = number
  default     = 1024

  validation {
    condition     = var.insights_query_string_length >= 256 && var.insights_query_string_length <= 4500
    error_message = "insights_query_string_length must be between 256 and 4500."
  }
}

variable "insights_query_plans_per_minute" {
  description = "Number of query execution plans sampled per minute by Query Insights (0-20)."
  type        = number
  default     = 5

  validation {
    condition     = var.insights_query_plans_per_minute >= 0 && var.insights_query_plans_per_minute <= 20
    error_message = "insights_query_plans_per_minute must be between 0 and 20."
  }
}

################################################################################
# Metadata
################################################################################

variable "labels" {
  description = "Additional GCP labels merged onto the instance and replicas. Standardized labels (managed_by, environment, database_engine, instance, role) are always enforced."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "GCP label keys must start with a lowercase letter and keys/values may contain only lowercase letters, digits, underscores, and hyphens (max 63 chars)."
  }
}
