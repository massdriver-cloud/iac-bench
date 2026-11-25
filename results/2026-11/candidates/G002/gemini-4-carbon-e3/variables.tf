variable "name" {
  description = "Logical name for the PostgreSQL instance (without environment suffix). The Cloud SQL instance will be named '<name>-<environment>'."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,48}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, not end with a hyphen, and be at most 50 characters."
  }

  validation {
    condition     = !can(regex("-(dev|staging|prod)$", var.name))
    error_message = "name must not end with '-dev', '-staging', or '-prod'; the module appends '-<environment>' automatically."
  }
}

variable "environment" {
  description = "Target environment ('dev', 'staging', or 'prod'). Determines the VPC network ('apps-<environment>') and environment-specific resilience defaults."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of 'dev', 'staging', or 'prod'."
  }
}

variable "region" {
  description = "Google Cloud region for the primary Cloud SQL instance. Defaults to the region configured on the Google provider."
  type        = string
  default     = null

  validation {
    condition     = var.region == null || can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid Google Cloud region name (for example, 'us-central1') or null to inherit the provider region."
  }
}

variable "database_version" {
  description = "Cloud SQL for PostgreSQL major version."
  type        = string
  default     = "POSTGRES_16"
  nullable    = false

  validation {
    condition = contains([
      "POSTGRES_14",
      "POSTGRES_15",
      "POSTGRES_16",
      "POSTGRES_17",
      "POSTGRES_18",
    ], var.database_version)
    error_message = "database_version must be a supported Cloud SQL PostgreSQL major version (POSTGRES_14 through POSTGRES_18)."
  }
}

variable "edition" {
  description = "Cloud SQL edition ('ENTERPRISE' or 'ENTERPRISE_PLUS')."
  type        = string
  default     = "ENTERPRISE"
  nullable    = false

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  }
}

variable "tier" {
  description = "Machine tier for the primary instance (for example, 'db-custom-2-8192' on ENTERPRISE or 'db-perf-optimized-N-8' on ENTERPRISE_PLUS)."
  type        = string
  default     = "db-custom-2-8192"
  nullable    = false

  validation {
    condition     = can(regex("^db-(custom-[0-9]+-[0-9]+|perf-optimized-N-[0-9]+|f1-micro|g1-small)$", var.tier))
    error_message = "tier must be a valid Cloud SQL PostgreSQL machine tier (db-custom-<vcpu>-<memory_mb>, db-perf-optimized-N-<vcpu>, db-f1-micro, or db-g1-small)."
  }
}

variable "data_cache_enabled" {
  description = "Whether to enable local SSD data cache on the primary instance (supported only on ENTERPRISE_PLUS)."
  type        = bool
  default     = false
  nullable    = false
}

variable "availability_type" {
  description = "Availability topology for the primary instance ('REGIONAL' for high availability or 'ZONAL'). When null, defaults to 'REGIONAL' in prod and 'ZONAL' in dev/staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be 'ZONAL', 'REGIONAL', or null."
  }
}

variable "disk_type" {
  description = "Storage media type for the primary instance ('PD_SSD' or 'HYPERDISK_BALANCED')."
  type        = string
  default     = "PD_SSD"
  nullable    = false

  validation {
    condition     = contains(["PD_SSD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be 'PD_SSD' or 'HYPERDISK_BALANCED'."
  }
}

variable "disk_size_gb" {
  description = "Initial storage size in GiB for the primary instance. Automatic storage increases are always enabled."
  type        = number
  default     = 20
  nullable    = false

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be an integer between 10 and 65536."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum storage size in GiB to which automatic storage increases may grow (0 means no limit)."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = (var.disk_autoresize_limit_gb == 0 || (var.disk_autoresize_limit_gb >= 10 && var.disk_autoresize_limit_gb <= 65536)) && floor(var.disk_autoresize_limit_gb) == var.disk_autoresize_limit_gb
    error_message = "disk_autoresize_limit_gb must be 0 (unlimited) or an integer between 10 and 65536."
  }
}

variable "database_flags" {
  description = "PostgreSQL database flags (name => value) owned by the DBA team. Merged over operational defaults; mandatory IAM authentication and security audit flags cannot be disabled."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for flag in ["cloudsql.iam_authentication", "cloudsql.enable_pgaudit", "log_connections", "log_disconnections"] :
      lookup(var.database_flags, flag, "on") == "on"
    ])
    error_message = "Mandatory security and identity audit flags ('cloudsql.iam_authentication', 'cloudsql.enable_pgaudit', 'log_connections', 'log_disconnections') must remain 'on'."
  }

  validation {
    condition = (
      !contains(keys(var.database_flags), "pgaudit.log") ||
      (trimspace(lookup(var.database_flags, "pgaudit.log", "all")) != "" && lower(trimspace(lookup(var.database_flags, "pgaudit.log", "all"))) != "none")
    )
    error_message = "pgaudit.log may be tuned for audit scope (for example, 'all' or 'ddl,role,write') but cannot be empty or 'none'."
  }
}

variable "backup_configuration" {
  description = "Automated backup and point-in-time recovery settings. Automated daily backups are always enabled; null attributes inherit environment defaults."
  type = object({
    start_time                     = optional(string, "03:00")
    location                       = optional(string)
    retained_backups               = optional(number)
    transaction_log_retention_days = optional(number)
    point_in_time_recovery_enabled = optional(bool)
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_configuration.start_time))
    error_message = "backup_configuration.start_time must be in 24-hour 'HH:MM' UTC format (for example, '03:00')."
  }

  validation {
    condition = (
      var.backup_configuration.retained_backups == null ||
      (
        var.backup_configuration.retained_backups >= 7 &&
        var.backup_configuration.retained_backups <= 365 &&
        floor(var.backup_configuration.retained_backups) == var.backup_configuration.retained_backups
      )
    )
    error_message = "backup_configuration.retained_backups must be null or an integer between 7 and 365."
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
    error_message = "backup_configuration.transaction_log_retention_days must be null or an integer between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Preferred weekly maintenance window (UTC) and update track for the primary instance."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 4)
    update_track = optional(string, "stable")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day
    error_message = "maintenance_window.day must be an integer between 1 (Monday) and 7 (Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour
    error_message = "maintenance_window.hour must be an integer between 0 and 23 (UTC)."
  }

  validation {
    condition     = contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be one of 'canary', 'stable', or 'week5'."
  }
}

variable "query_insights" {
  description = "Query Insights tuning parameters. Query Insights, application tag recording, and client address recording are always enabled."
  type = object({
    query_plans_per_minute = optional(number, 5)
    query_string_length    = optional(number, 1024)
  })
  default  = {}
  nullable = false

  validation {
    condition = (
      var.query_insights.query_plans_per_minute >= 0 &&
      var.query_insights.query_plans_per_minute <= 20 &&
      floor(var.query_insights.query_plans_per_minute) == var.query_insights.query_plans_per_minute
    )
    error_message = "query_insights.query_plans_per_minute must be an integer between 0 and 20."
  }

  validation {
    condition = (
      var.query_insights.query_string_length >= 256 &&
      var.query_insights.query_string_length <= 4500 &&
      floor(var.query_insights.query_string_length) == var.query_insights.query_string_length
    )
    error_message = "query_insights.query_string_length must be an integer between 256 and 4500."
  }
}

variable "databases" {
  description = "Map of logical PostgreSQL databases to manage on the instance, keyed by database name."
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string, "en_US.UTF8")
    deletion_policy = optional(string, "DELETE")
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for db_name, db in var.databases :
      can(regex("^[a-zA-Z_][a-zA-Z0-9_-]{0,62}$", db_name)) &&
      !contains(["postgres", "template0", "template1", "cloudsqladmin"], lower(db_name)) &&
      contains(["ABANDON", "DELETE"], db.deletion_policy)
    ])
    error_message = "Each database name must be a valid non-system PostgreSQL identifier (1-63 chars) and deletion_policy must be 'ABANDON' or 'DELETE'."
  }
}

variable "iam_users" {
  description = "Google user email addresses (engineers/DBAs) to provision as CLOUD_IAM_USER database accounts."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for email in var.iam_users :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email)) && !endswith(lower(email), ".gserviceaccount.com")
    ])
    error_message = "Each entry in iam_users must be a valid Google user email address (use iam_service_accounts for '*.gserviceaccount.com' identities)."
  }
}

variable "iam_service_accounts" {
  description = "Google service account email addresses (GKE Workload Identity or Compute Engine workloads) to provision as CLOUD_IAM_SERVICE_ACCOUNT database accounts."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for sa in var.iam_service_accounts :
      can(regex("^[^@\\s]+@[a-z0-9.-]+\\.gserviceaccount\\.com$", sa))
    ])
    error_message = "Each entry in iam_service_accounts must be a full Google service account email ending in '.gserviceaccount.com'."
  }
}

variable "iam_groups" {
  description = "Google Group email addresses to provision as CLOUD_IAM_GROUP database accounts."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for group in var.iam_groups :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", group)) && !endswith(lower(group), ".gserviceaccount.com")
    ])
    error_message = "Each entry in iam_groups must be a valid Google Group email address."
  }
}

variable "grant_iam_roles" {
  description = "Whether to grant roles/cloudsql.client and roles/cloudsql.instanceUser on the project (scoped via IAM Condition to this instance and its read replicas) for all configured IAM users, service accounts, and groups."
  type        = bool
  default     = true
  nullable    = false
}

variable "abandon_users_on_destroy" {
  description = "When true, sets deletion_policy = 'ABANDON' on google_sql_user resources so removing a user who owns PostgreSQL objects does not fail role drop in OpenTofu."
  type        = bool
  default     = true
  nullable    = false
}

variable "ssl_mode" {
  description = "TLS enforcement mode for client connections ('ENCRYPTED_ONLY' or 'TRUSTED_CLIENT_CERTIFICATE_REQUIRED'). Unencrypted connections are never permitted."
  type        = string
  default     = "ENCRYPTED_ONLY"
  nullable    = false

  validation {
    condition     = contains(["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be 'ENCRYPTED_ONLY' or 'TRUSTED_CLIENT_CERTIFICATE_REQUIRED'."
  }
}

variable "connector_enforcement" {
  description = "Whether all connections must go through Cloud SQL connectors/Auth Proxy ('NOT_REQUIRED' or 'REQUIRED')."
  type        = string
  default     = "NOT_REQUIRED"
  nullable    = false

  validation {
    condition     = contains(["NOT_REQUIRED", "REQUIRED"], var.connector_enforcement)
    error_message = "connector_enforcement must be 'NOT_REQUIRED' or 'REQUIRED'."
  }
}

variable "allocated_ip_range" {
  description = "Optional name of a specific allocated Private Services Access IP range in 'apps-<environment>' to use for this instance."
  type        = string
  default     = null
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS crypto key resource ID for customer-managed encryption keys (CMEK) on the primary instance."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Overrides instance deletion protection (both OpenTofu and Cloud SQL API). When null, defaults to true in 'prod' and false in 'dev' and 'staging'."
  type        = bool
  default     = null
}

variable "read_replicas" {
  description = "Optional read replicas keyed by replica suffix (named '<name>-<environment>-replica-<key>'). Replicas inherit the VPC, TLS policy, PostgreSQL version, edition, Query Insights, and mandatory audit/IAM flags."
  type = map(object({
    region                   = optional(string)
    tier                     = optional(string)
    availability_type        = optional(string, "ZONAL")
    disk_type                = optional(string)
    disk_size_gb             = optional(number)
    disk_autoresize_limit_gb = optional(number)
    data_cache_enabled       = optional(bool)
    allocated_ip_range       = optional(string)
    encryption_key_name      = optional(string)
    database_flags           = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for key, replica in var.read_replicas :
      can(regex("^[a-z0-9]([a-z0-9-]{0,20}[a-z0-9])?$", key)) &&
      contains(["ZONAL", "REGIONAL"], replica.availability_type) &&
      (replica.region == null || can(regex("^[a-z]+-[a-z]+[0-9]+$", replica.region))) &&
      (replica.tier == null || can(regex("^db-(custom-[0-9]+-[0-9]+|perf-optimized-N-[0-9]+|f1-micro|g1-small)$", replica.tier))) &&
      (replica.disk_type == null || contains(["PD_SSD", "HYPERDISK_BALANCED"], replica.disk_type)) &&
      (replica.disk_size_gb == null || (replica.disk_size_gb >= 10 && replica.disk_size_gb <= 65536 && floor(replica.disk_size_gb) == replica.disk_size_gb)) &&
      (replica.disk_autoresize_limit_gb == null || ((replica.disk_autoresize_limit_gb == 0 || (replica.disk_autoresize_limit_gb >= 10 && replica.disk_autoresize_limit_gb <= 65536)) && floor(replica.disk_autoresize_limit_gb) == replica.disk_autoresize_limit_gb)) &&
      alltrue([
        for flag in ["cloudsql.iam_authentication", "cloudsql.enable_pgaudit", "log_connections", "log_disconnections"] :
        lookup(replica.database_flags, flag, "on") == "on"
      ]) &&
      (
        !contains(keys(replica.database_flags), "pgaudit.log") ||
        (trimspace(lookup(replica.database_flags, "pgaudit.log", "all")) != "" && lower(trimspace(lookup(replica.database_flags, "pgaudit.log", "all"))) != "none")
      )
    ])
    error_message = "Each read replica must use a valid lowercase alphanumeric key (1-22 chars), valid region/tier/availability_type/disk_type/disk_size_gb, and must not disable mandatory IAM authentication or audit flags."
  }
}

variable "labels" {
  description = "Additional user labels to attach to Cloud SQL instances. Merged with standard labels ('environment', 'instance', 'managed_by', 'role', 'replica')."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) &&
      can(regex("^[a-z0-9_-]{0,63}$", v)) &&
      !contains(["environment", "instance", "managed_by", "role", "replica"], k)
    ])
    error_message = "Label keys and values must satisfy Google Cloud label naming rules, and must not override reserved module keys ('environment', 'instance', 'managed_by', 'role', 'replica')."
  }
}
