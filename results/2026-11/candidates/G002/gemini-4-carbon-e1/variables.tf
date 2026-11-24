# -----------------------------------------------------------------------------
# Identity & Environment (Required)
# -----------------------------------------------------------------------------

variable "name" {
  description = "Short logical name for the PostgreSQL instance (for example, 'orders' or 'billing'). Combined with environment to form the Cloud SQL instance name 'pg-<environment>-<name>'."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,46}[a-z0-9]$|^[a-z]$", var.name))
    error_message = "name must be 1-48 characters, start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and not end with a hyphen."
  }
}

variable "environment" {
  description = "Target deployment environment ('dev', 'staging', or 'prod'). Determines the private VPC network ('apps-<environment>'), instance naming prefix, and baseline resilience defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: 'dev', 'staging', 'prod'."
  }
}

# -----------------------------------------------------------------------------
# Location & Topology
# -----------------------------------------------------------------------------

variable "region" {
  description = "Google Cloud region for the primary Cloud SQL instance. When null, inherits the region configured on the Google provider."
  type        = string
  default     = null

  validation {
    condition     = var.region == null || can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be null (to inherit from the Google provider) or a valid GCP region name such as 'us-central1'."
  }
}

variable "availability_type" {
  description = "High availability mode ('REGIONAL' for multi-zone synchronous standby or 'ZONAL' for single-zone). Defaults to 'REGIONAL' in prod and 'ZONAL' in dev and staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be 'ZONAL', 'REGIONAL', or null (environment default)."
  }
}

variable "zone" {
  description = "Optional preferred primary Compute Engine zone within the target region (for example, to co-locate with GKE node pools or GCE workloads)."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "zone must be null or a valid GCP zone name such as 'us-central1-a'."
  }
}

variable "secondary_zone" {
  description = "Optional preferred standby Compute Engine zone when availability_type is 'REGIONAL'. Must differ from zone when both are set."
  type        = string
  default     = null

  validation {
    condition     = var.secondary_zone == null || can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.secondary_zone))
    error_message = "secondary_zone must be null or a valid GCP zone name such as 'us-central1-b'."
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL Engine, Edition & Sizing
# -----------------------------------------------------------------------------

variable "database_version" {
  description = "Cloud SQL PostgreSQL major engine version."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17", "POSTGRES_18"], var.database_version)
    error_message = "database_version must be a supported PostgreSQL major version: POSTGRES_14, POSTGRES_15, POSTGRES_16, POSTGRES_17, or POSTGRES_18."
  }
}

variable "edition" {
  description = "Cloud SQL edition ('ENTERPRISE' or 'ENTERPRISE_PLUS')."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier for the primary instance (for example, 'db-custom-2-8192', 'db-custom-4-16384', or 'db-perf-optimized-N-8')."
  type        = string
  default     = "db-custom-2-8192"

  validation {
    condition     = can(regex("^db-[a-zA-Z0-9-]+$", var.tier))
    error_message = "tier must be a valid Cloud SQL machine tier starting with 'db-' (for example, 'db-custom-2-8192' or 'db-perf-optimized-N-8')."
  }
}

variable "data_cache_enabled" {
  description = "Enable local SSD read cache. Only supported when edition is 'ENTERPRISE_PLUS'."
  type        = bool
  default     = false
}

variable "managed_connection_pooling_enabled" {
  description = "Enable Cloud SQL managed connection pooling on the instance. Only supported when edition is 'ENTERPRISE_PLUS'."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Storage Configuration
# -----------------------------------------------------------------------------

variable "disk_type" {
  description = "Storage media type for the primary instance ('PD_SSD', 'PD_HDD', or 'HYPERDISK_BALANCED')."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be one of: 'PD_SSD', 'PD_HDD', 'HYPERDISK_BALANCED'."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GiB. When disk_autoresize is enabled, Cloud SQL grows storage automatically from this baseline."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be a whole number between 10 and 65536."
  }
}

variable "disk_autoresize" {
  description = "Automatically expand storage capacity before disk exhaustion occurs."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound in GiB for automatic disk expansion. Set to 0 for no upper limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb == 0 || (var.disk_autoresize_limit_gb >= 10 && floor(var.disk_autoresize_limit_gb) == var.disk_autoresize_limit_gb)
    error_message = "disk_autoresize_limit_gb must be 0 (unlimited) or a whole number >= 10."
  }
}

variable "provisioned_iops" {
  description = "Optional custom provisioned IOPS (supported with HYPERDISK_BALANCED or extreme PD_SSD configurations)."
  type        = number
  default     = null
}

variable "provisioned_throughput_mbps" {
  description = "Optional custom provisioned storage throughput in MiB/s (supported with HYPERDISK_BALANCED)."
  type        = number
  default     = null
}

# -----------------------------------------------------------------------------
# Private Networking, TLS & Encryption
# -----------------------------------------------------------------------------

variable "allocated_ip_range" {
  description = "Optional name of a specific Private Services Access IP range in 'apps-<environment>' to allocate the instance IP from."
  type        = string
  default     = null
}

variable "ssl_mode" {
  description = "TLS enforcement mode on private VPC connections. Plaintext connections are prohibited; choose 'ENCRYPTED_ONLY' (default) or 'TRUSTED_CLIENT_CERTIFICATE_REQUIRED'."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be 'ENCRYPTED_ONLY' or 'TRUSTED_CLIENT_CERTIFICATE_REQUIRED'. Unencrypted connections are not permitted."
  }
}

variable "connector_enforcement" {
  description = "Whether to require Cloud SQL Auth Proxy / Language Connectors for all connections ('NOT_REQUIRED' allows direct TLS + IAM token over private IP; 'REQUIRED' enforces Cloud SQL connectors)."
  type        = string
  default     = "NOT_REQUIRED"

  validation {
    condition     = contains(["NOT_REQUIRED", "REQUIRED"], var.connector_enforcement)
    error_message = "connector_enforcement must be 'NOT_REQUIRED' or 'REQUIRED'."
  }
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS crypto key resource ID for Customer-Managed Encryption Keys (CMEK) in the primary instance region."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Protect the Cloud SQL instance against accidental deletion via both OpenTofu and the Cloud SQL API. Defaults to true in prod and false in dev and staging."
  type        = bool
  default     = null
}

# -----------------------------------------------------------------------------
# PostgreSQL Tuning, Auditing & Observability
# -----------------------------------------------------------------------------

variable "pgaudit_log" {
  description = "Comma-separated pgAudit statement classes to record in Cloud Logging for identity-attributed security auditing (for example, 'ddl,role' or 'read,write,ddl,role'). Cannot be disabled."
  type        = string
  default     = "ddl,role"

  validation {
    condition = (
      trimspace(var.pgaudit_log) != "" &&
      lower(trimspace(var.pgaudit_log)) != "none" &&
      alltrue([
        for token in split(",", var.pgaudit_log) :
        can(regex("^-?(read|write|function|role|ddl|misc|misc_set|all)$", lower(trimspace(token))))
      ])
    )
    error_message = "pgaudit_log must be a non-empty comma-separated list of valid pgAudit classes (read, write, function, role, ddl, misc, misc_set, all, optionally prefixed with '-' for exclusions) and cannot be 'none'."
  }
}

variable "database_flags" {
  description = "Map of PostgreSQL database flags owned by the DBA team (for example, work_mem, max_connections, autovacuum settings, or log_min_duration_statement). Security/audit flags (cloudsql.iam_authentication, cloudsql.enable_pgaudit, log_connections, log_disconnections) are enforced by the module and cannot be overridden here."
  type        = map(string)
  default     = {}

  validation {
    condition = length(setintersection(
      toset(keys(var.database_flags)),
      toset([
        "cloudsql.iam_authentication",
        "cloudsql.enable_pgaudit",
        "log_connections",
        "log_disconnections",
        "pgaudit.log",
      ])
    )) == 0
    error_message = "database_flags cannot override mandatory security and audit flags (cloudsql.iam_authentication, cloudsql.enable_pgaudit, log_connections, log_disconnections). To configure audited statement classes, set pgaudit_log instead of pgaudit.log."
  }
}

variable "insights_config" {
  description = "Cloud SQL Query Insights configuration for query performance diagnostics and client attribution."
  type = object({
    enabled                 = optional(bool, true)
    query_plans_per_minute  = optional(number, 5)
    query_string_length     = optional(number, 1024)
    record_application_tags = optional(bool, true)
    record_client_address   = optional(bool, true)
  })
  default = {}

  validation {
    condition = (
      var.insights_config.query_plans_per_minute >= 0 &&
      var.insights_config.query_plans_per_minute <= 20 &&
      var.insights_config.query_string_length >= 256 &&
      var.insights_config.query_string_length <= 4500
    )
    error_message = "insights_config.query_plans_per_minute must be between 0 and 20, and insights_config.query_string_length must be between 256 and 4500."
  }
}

# -----------------------------------------------------------------------------
# Backups, Point-in-Time Recovery & Maintenance
# -----------------------------------------------------------------------------

variable "backup_configuration" {
  description = "Automated backup and WAL retention settings. Automated backups are always enabled. When null, point_in_time_recovery_enabled, retained_backups, and transaction_log_retention_days use environment-aware defaults."
  type = object({
    start_time                     = optional(string, "02:00")
    location                       = optional(string, null)
    point_in_time_recovery_enabled = optional(bool, null)
    retained_backups               = optional(number, null)
    transaction_log_retention_days = optional(number, null)
  })
  default = {}

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_configuration.start_time))
    error_message = "backup_configuration.start_time must be in 24-hour HH:MM UTC format (for example, '02:00')."
  }

  validation {
    condition = (
      var.backup_configuration.retained_backups == null ||
      (
        var.backup_configuration.retained_backups >= 1 &&
        var.backup_configuration.retained_backups <= 365 &&
        floor(var.backup_configuration.retained_backups) == var.backup_configuration.retained_backups
      )
    )
    error_message = "backup_configuration.retained_backups must be null or a whole number between 1 and 365."
  }

  validation {
    condition = (
      var.backup_configuration.transaction_log_retention_days == null ||
      (
        var.backup_configuration.transaction_log_retention_days >= 1 &&
        var.backup_configuration.transaction_log_retention_days <= 35 &&
        floor(var.backup_configuration.transaction_log_retention_days) == var.backup_configuration.transaction_log_retention_days
      )
    )
    error_message = "backup_configuration.transaction_log_retention_days must be null or a whole number between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC (day 1 = Monday through 7 = Sunday) and update track ('stable', 'canary', or 'week5')."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition = (
      var.maintenance_window.day >= 1 &&
      var.maintenance_window.day <= 7 &&
      floor(var.maintenance_window.day) == var.maintenance_window.day &&
      var.maintenance_window.hour >= 0 &&
      var.maintenance_window.hour <= 23 &&
      floor(var.maintenance_window.hour) == var.maintenance_window.hour &&
      contains(["stable", "canary", "week5"], var.maintenance_window.update_track)
    )
    error_message = "maintenance_window requires day in 1..7, hour in 0..23, and update_track in ['stable', 'canary', 'week5']."
  }
}

# -----------------------------------------------------------------------------
# Logical Databases & Google Identity Access
# -----------------------------------------------------------------------------

variable "databases" {
  description = "Map of logical PostgreSQL databases to manage on the instance, keyed by database name."
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string, "en_US.UTF8")
    deletion_policy = optional(string, "DELETE")
  }))
  default = {}

  validation {
    condition = alltrue([
      for db_name, db in var.databases :
      can(regex("^[a-zA-Z_][a-zA-Z0-9_-]{0,62}$", db_name)) &&
      !contains(["postgres", "template0", "template1", "cloudsqladmin"], lower(db_name)) &&
      contains(["DELETE", "ABANDON"], db.deletion_policy)
    ])
    error_message = "Each key in databases must be a valid PostgreSQL identifier (1-63 chars), must not be a reserved system database (postgres, template0, template1, cloudsqladmin), and deletion_policy must be 'DELETE' or 'ABANDON'."
  }
}

variable "iam_users" {
  description = "Set of human engineer Google identity email addresses granted IAM database login on this instance (created as CLOUD_IAM_USER)."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.iam_users :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email)) && !endswith(lower(email), ".gserviceaccount.com")
    ])
    error_message = "Every entry in iam_users must be a valid user email address and must not be a '.gserviceaccount.com' address (use iam_service_accounts for workload service accounts)."
  }
}

variable "iam_service_accounts" {
  description = "Set of workload Google service account email addresses (GKE Workload Identity or Compute Engine service accounts) granted IAM database login on this instance (created as CLOUD_IAM_SERVICE_ACCOUNT with '.gserviceaccount.com' stripped automatically)."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.iam_service_accounts :
      can(regex("^[^@\\s]+@[^@\\s]+\\.gserviceaccount\\.com$", email))
    ])
    error_message = "Every entry in iam_service_accounts must be a full Google service account email ending in '.gserviceaccount.com'."
  }
}

variable "iam_groups" {
  description = "Set of Google Cloud Identity / Workspace group email addresses granted IAM database login on this instance (created as CLOUD_IAM_GROUP)."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.iam_groups :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email)) && !endswith(lower(email), ".gserviceaccount.com")
    ])
    error_message = "Every entry in iam_groups must be a valid group email address and must not end in '.gserviceaccount.com'."
  }
}

variable "manage_iam_bindings" {
  description = "Automatically create instance-scoped project IAM bindings (roles/cloudsql.client and roles/cloudsql.instanceUser) for identities in iam_users, iam_service_accounts, and iam_groups."
  type        = bool
  default     = true
}

variable "sql_user_deletion_policy" {
  description = "Deletion behavior for managed Cloud SQL IAM users ('DELETE' drops the PostgreSQL role; 'ABANDON' removes Terraform state tracking if the user still owns database objects)."
  type        = string
  default     = "DELETE"

  validation {
    condition     = contains(["DELETE", "ABANDON"], var.sql_user_deletion_policy)
    error_message = "sql_user_deletion_policy must be 'DELETE' or 'ABANDON'."
  }
}

# -----------------------------------------------------------------------------
# Read Replicas
# -----------------------------------------------------------------------------

variable "read_replicas" {
  description = "Map of read replicas to provision for read scaling or analytics workloads. Each replica inherits private VPC networking, TLS, and mandatory IAM/pgAudit flags from the primary instance."
  type = map(object({
    region              = optional(string, null)
    zone                = optional(string, null)
    availability_type   = optional(string, "ZONAL")
    tier                = optional(string, null)
    disk_type           = optional(string, null)
    disk_size_gb        = optional(number, null)
    allocated_ip_range  = optional(string, null)
    encryption_key_name = optional(string, null)
    deletion_protection = optional(bool, null)
    database_flags      = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, replica in var.read_replicas :
      can(regex("^[a-z0-9][a-z0-9-]{0,18}[a-z0-9]$|^[a-z0-9]$", key)) &&
      contains(["ZONAL", "REGIONAL"], replica.availability_type) &&
      (replica.tier == null || can(regex("^db-[a-zA-Z0-9-]+$", replica.tier))) &&
      (replica.disk_type == null || contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], replica.disk_type)) &&
      (replica.disk_size_gb == null || (replica.disk_size_gb >= 10 && floor(replica.disk_size_gb) == replica.disk_size_gb)) &&
      length(setintersection(
        toset(keys(replica.database_flags)),
        toset([
          "cloudsql.iam_authentication",
          "cloudsql.enable_pgaudit",
          "log_connections",
          "log_disconnections",
          "pgaudit.log",
        ])
      )) == 0
    ])
    error_message = "Read replica keys must be 1-20 lowercase alphanumeric/hyphen characters; replica settings must use valid availability_type, tier, disk_type, and disk_size_gb values; and replica database_flags cannot override mandatory security/audit flags."
  }
}

# -----------------------------------------------------------------------------
# Resource Labels
# -----------------------------------------------------------------------------

variable "labels" {
  description = "Additional GCP user_labels to attach to the Cloud SQL primary and replica instances. Standard governance labels (environment, service, managed_by, instance_role) are applied automatically."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "GCP label keys must start with a lowercase letter and contain only lowercase letters, numbers, underscores, or hyphens (max 63 chars); values may contain lowercase letters, numbers, underscores, or hyphens (max 63 chars)."
  }
}
