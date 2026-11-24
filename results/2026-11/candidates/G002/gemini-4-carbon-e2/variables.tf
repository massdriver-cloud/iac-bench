# -----------------------------------------------------------------------------
# Instance Identity & Environment Placement
# -----------------------------------------------------------------------------

variable "name" {
  description = "Logical name of the PostgreSQL instance (for example, 'orders' or 'billing'). Combined with var.environment unless already suffixed."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,48}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, end with a letter or number, and be at most 50 characters."
  }
}

variable "environment" {
  description = "Deployment environment ('dev', 'staging', or 'prod'). Selects the corresponding private VPC network (apps-dev, apps-staging, apps-prod) and baseline resilience defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of 'dev', 'staging', or 'prod'."
  }
}

variable "region" {
  description = "Google Cloud region for the primary Cloud SQL instance. Defaults to the region configured on the Google provider (or 'us-central1' if unset)."
  type        = string
  default     = null

  validation {
    condition     = var.region == null || can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must be a valid Google Cloud region name such as 'us-central1' or 'europe-west1'."
  }
}

variable "allocated_ip_range" {
  description = "Optional name of a specific reserved Private Services Access IP range in the apps-<environment> VPC network. Leave null to let Cloud SQL select automatically from the network's PSA ranges."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Engine, Edition, Compute & High Availability (DBA-Owned Sizing & Lifecycle)
# -----------------------------------------------------------------------------

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version (for example, 'POSTGRES_15', 'POSTGRES_16', 'POSTGRES_17')."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version matching '^POSTGRES_[0-9]+$' (for example, 'POSTGRES_16')."
  }
}

variable "edition" {
  description = "Cloud SQL edition: 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be either 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  }
}

variable "tier" {
  description = "Machine tier for the primary instance (for example, 'db-custom-2-8192' for ENTERPRISE or 'db-perf-optimized-N-2' for ENTERPRISE_PLUS)."
  type        = string
  default     = "db-custom-2-8192"

  validation {
    condition     = trimspace(var.tier) != ""
    error_message = "tier must not be empty."
  }
}

variable "enable_data_cache" {
  description = "Enable local SSD data cache on the primary instance (supported only with edition = 'ENTERPRISE_PLUS')."
  type        = bool
  default     = false
}

variable "availability_type" {
  description = "High-availability topology for the primary instance ('REGIONAL' or 'ZONAL'). When null, defaults to 'REGIONAL' in prod and 'ZONAL' in dev/staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be 'ZONAL', 'REGIONAL', or null."
  }
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------

variable "disk_type" {
  description = "Storage media type for the primary instance ('PD_SSD', 'PD_HDD', or 'HYPERDISK_BALANCED')."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be one of 'PD_SSD', 'PD_HDD', or 'HYPERDISK_BALANCED'."
  }
}

variable "disk_size_gb" {
  description = "Initial storage size in GB for the primary instance."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be an integer between 10 and 65536."
  }
}

variable "disk_autoresize" {
  description = "Automatically increase storage size when available space runs low."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum storage size in GB to which storage can auto-expand (0 means no limit)."
  type        = number
  default     = 0

  validation {
    condition     = (var.disk_autoresize_limit_gb == 0 || (var.disk_autoresize_limit_gb >= 10 && var.disk_autoresize_limit_gb <= 65536)) && floor(var.disk_autoresize_limit_gb) == var.disk_autoresize_limit_gb
    error_message = "disk_autoresize_limit_gb must be 0 (unlimited) or an integer between 10 and 65536."
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL Tuning & Logical Databases
# -----------------------------------------------------------------------------

variable "database_flags" {
  description = "DBA-managed PostgreSQL flags (name => value), such as 'max_connections', 'work_mem', 'random_page_cost', 'log_min_duration_statement', or 'pgaudit.log'. Security invariants (cloudsql.iam_authentication, cloudsql.enable_pgaudit, log_connections, log_disconnections) are always enforced to 'on'."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.database_flags :
      v == "on" if contains([
        "cloudsql.iam_authentication",
        "cloudsql.enable_pgaudit",
        "log_connections",
        "log_disconnections",
      ], k)
    ])
    error_message = "Security and audit flags ('cloudsql.iam_authentication', 'cloudsql.enable_pgaudit', 'log_connections', 'log_disconnections') are platform invariants and cannot be disabled."
  }
}

variable "databases" {
  description = "Map of application PostgreSQL databases to create on the instance, keyed by database name."
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string, "en_US.UTF8")
    deletion_policy = optional(string, "DELETE")
  }))
  default = {}

  validation {
    condition = alltrue([
      for db_name, cfg in var.databases :
      trimspace(db_name) != "" && contains(["DELETE", "ABANDON"], cfg.deletion_policy)
    ])
    error_message = "Each database key must be non-empty and deletion_policy must be 'DELETE' or 'ABANDON'."
  }
}

# -----------------------------------------------------------------------------
# Identity-Based Database Access & Auditing
# -----------------------------------------------------------------------------

variable "iam_users" {
  description = "Set of Google user emails (engineers and DBAs) provisioned as CLOUD_IAM_USER database accounts."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.iam_users :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email)) && !endswith(email, ".gserviceaccount.com")
    ])
    error_message = "iam_users must contain valid Google user email addresses; service accounts (*.gserviceaccount.com) belong in iam_service_accounts."
  }
}

variable "iam_service_accounts" {
  description = "Set of Google service account emails (GKE Workload Identity and Compute Engine workloads) provisioned as CLOUD_IAM_SERVICE_ACCOUNT database accounts."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for sa in var.iam_service_accounts :
      can(regex("^[^@\\s]+@[^@\\s]+\\.gserviceaccount\\.com$", sa))
    ])
    error_message = "iam_service_accounts must contain valid Google Cloud service account emails ending in '.gserviceaccount.com'."
  }
}

variable "iam_groups" {
  description = "Set of Google Group emails provisioned as CLOUD_IAM_GROUP database accounts (members still authenticate and are audited via their individual Google identities)."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for grp in var.iam_groups :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", grp)) && !endswith(grp, ".gserviceaccount.com")
    ])
    error_message = "iam_groups must contain valid Google Group email addresses."
  }
}

variable "manage_iam_bindings" {
  description = "Grant instance-scoped roles/cloudsql.client and roles/cloudsql.instanceUser IAM bindings (via IAM Conditions) to principals in iam_users, iam_service_accounts, and iam_groups."
  type        = bool
  default     = true
}

variable "user_deletion_policy" {
  description = "Deletion policy for Cloud SQL IAM users: null (drop PostgreSQL user on removal) or 'ABANDON' (retain PostgreSQL role if it owns database objects while revoking IAM login)."
  type        = string
  default     = null

  validation {
    condition     = var.user_deletion_policy == null || var.user_deletion_policy == "ABANDON"
    error_message = "user_deletion_policy must be null or 'ABANDON'."
  }
}

# -----------------------------------------------------------------------------
# Backups, Maintenance, Observability & Protection
# -----------------------------------------------------------------------------

variable "backup_configuration" {
  description = "Tuning parameters for automated backups and Point-in-Time Recovery (both are always enabled on primary instances). Null retention fields use environment defaults (prod: 30 backups / 7 PITR days, staging: 14 / 7, dev: 7 / 3)."
  type = object({
    start_time                     = optional(string, "03:00")
    location                       = optional(string, null)
    retained_backups               = optional(number, null)
    transaction_log_retention_days = optional(number, null)
  })
  default = {}

  validation {
    condition = (
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_configuration.start_time)) &&
      (var.backup_configuration.retained_backups == null || (var.backup_configuration.retained_backups >= 1 && var.backup_configuration.retained_backups <= 365)) &&
      (var.backup_configuration.transaction_log_retention_days == null || (var.backup_configuration.transaction_log_retention_days >= 1 && var.backup_configuration.transaction_log_retention_days <= 35))
    )
    error_message = "backup_configuration.start_time must be HH:MM (UTC), retained_backups must be 1..365, and transaction_log_retention_days must be 1..35."
  }
}

variable "maintenance_window" {
  description = "Preferred weekly maintenance window (UTC) and Cloud SQL update track."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 4)
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      floor(var.maintenance_window.day) == var.maintenance_window.day &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 &&
      floor(var.maintenance_window.hour) == var.maintenance_window.hour &&
      contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    )
    error_message = "maintenance_window.day must be 1..7 (Mon..Sun), hour must be 0..23, and update_track must be 'canary', 'stable', or 'week5'."
  }
}

variable "insights_config" {
  description = "Query Insights tuning parameters (Query Insights, application tag recording, and client address recording are always enabled)."
  type = object({
    query_plans_per_minute = optional(number, 5)
    query_string_length    = optional(number, 1024)
  })
  default = {}

  validation {
    condition = (
      var.insights_config.query_plans_per_minute >= 0 && var.insights_config.query_plans_per_minute <= 20 &&
      var.insights_config.query_string_length >= 256 && var.insights_config.query_string_length <= 4500
    )
    error_message = "insights_config.query_plans_per_minute must be 0..20 and query_string_length must be 256..4500."
  }
}

variable "deletion_protection" {
  description = "Protect the instance (and read replicas) against accidental deletion in both OpenTofu and the Google Cloud API/Console. When null, defaults to true in staging/prod and true in dev unless explicitly set false."
  type        = bool
  default     = true
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS key resource name for Customer-Managed Encryption Keys (CMEK) on the primary instance."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Read Replicas
# -----------------------------------------------------------------------------

variable "read_replicas" {
  description = "Map of read replicas keyed by replica suffix (for example, 'reporting' or 'analytics'), inheriting VPC, TLS, and IAM/audit invariants from the primary instance unless overridden where permitted."
  type = map(object({
    region                   = optional(string, null)
    tier                     = optional(string, null)
    availability_type        = optional(string, "ZONAL")
    disk_type                = optional(string, null)
    disk_size_gb             = optional(number, null)
    disk_autoresize          = optional(bool, null)
    disk_autoresize_limit_gb = optional(number, null)
    enable_data_cache        = optional(bool, null)
    database_flags           = optional(map(string), null)
    encryption_key_name      = optional(string, null)
  }))
  default = {}

  validation {
    condition = (
      length(var.read_replicas) <= 10 &&
      alltrue([
        for k, r in var.read_replicas :
        can(regex("^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$", k)) &&
        contains(["ZONAL", "REGIONAL"], r.availability_type) &&
        (r.disk_type == null || contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], r.disk_type)) &&
        (r.database_flags == null || alltrue([
          for fk, fv in r.database_flags :
          fv == "on" if contains([
            "cloudsql.iam_authentication",
            "cloudsql.enable_pgaudit",
            "log_connections",
            "log_disconnections",
          ], fk)
        ]))
      ])
    )
    error_message = "At most 10 read_replicas may be defined; keys must be lowercase alphanumeric/hyphens (<=20 chars), availability_type must be 'ZONAL' or 'REGIONAL', disk_type must be valid, and enforced security/audit flags cannot be disabled."
  }
}

# -----------------------------------------------------------------------------
# Labels
# -----------------------------------------------------------------------------

variable "labels" {
  description = "Additional user labels applied to Cloud SQL instances alongside standard module labels ('environment', 'managed_by')."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, digits, underscores, or hyphens (<=63 chars); values must be <=63 lowercase chars."
  }
}
