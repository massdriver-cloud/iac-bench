variable "name" {
  description = "Name of the primary Cloud SQL PostgreSQL instance. Must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens (max 63 characters)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name)) && !endswith(var.name, "-")
    error_message = "Instance name must start with a lowercase letter, end with a letter or digit, contain only lowercase letters, digits, and hyphens, and be at most 63 characters long."
  }
}

variable "environment" {
  description = "Target environment for the instance. Determines the VPC network (apps-<environment>) and environment-appropriate operational defaults (HA, backup retention, maintenance update track, deletion protection)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: \"dev\", \"staging\", \"prod\"."
  }
}

variable "region" {
  description = "GCP region for the primary instance. Defaults to the region configured on the Google provider."
  type        = string
  default     = null
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version (e.g., POSTGRES_15, POSTGRES_16, POSTGRES_17)."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a valid Cloud SQL PostgreSQL version (e.g., \"POSTGRES_15\", \"POSTGRES_16\", \"POSTGRES_17\")."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be either \"ENTERPRISE\" or \"ENTERPRISE_PLUS\"."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier (e.g., db-custom-2-7680 for ENTERPRISE or db-perf-optimized-N-2 for ENTERPRISE_PLUS). When null, selects an environment- and edition-appropriate default."
  type        = string
  default     = null
}

variable "availability_type" {
  description = "High availability mode: REGIONAL (HA with automatic failover) or ZONAL (single zone). Defaults to REGIONAL in prod and ZONAL in dev/staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be \"REGIONAL\", \"ZONAL\", or null."
  }
}

variable "zone" {
  description = "Preferred GCP zone for the primary instance (e.g., us-central1-a). Optional."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Preferred GCP zone for the standby replica when availability_type is REGIONAL. Optional."
  type        = string
  default     = null
}

variable "disk_size" {
  description = "Initial storage capacity in GB. Storage auto-resize is always enabled. Defaults to 20 GB (dev), 50 GB (staging), or 100 GB (prod)."
  type        = number
  default     = null

  validation {
    condition     = var.disk_size == null || (var.disk_size >= 10 && floor(var.disk_size) == var.disk_size)
    error_message = "disk_size must be a whole number of at least 10 GB."
  }
}

variable "disk_type" {
  description = "Storage disk type: PD_SSD, PD_HDD, or HYPERDISK_BALANCED."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be one of: \"PD_SSD\", \"PD_HDD\", \"HYPERDISK_BALANCED\"."
  }
}

variable "disk_autoresize_limit" {
  description = "Maximum storage size in GB to which the disk can automatically expand. Set to 0 for no upper limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit >= 0 && floor(var.disk_autoresize_limit) == var.disk_autoresize_limit
    error_message = "disk_autoresize_limit must be a non-negative integer."
  }
}

variable "database_flags" {
  description = "Map of PostgreSQL database flags to tune instance behavior (e.g., max_connections, work_mem, shared_buffers, pgaudit.log, log_min_duration_statement). Mandatory security and auditing flags (cloudsql.iam_authentication, cloudsql.enable_pgaudit, log_connections, log_disconnections) cannot be disabled."
  type        = map(string)
  default     = {}

  validation {
    condition     = lookup(var.database_flags, "cloudsql.iam_authentication", "on") == "on"
    error_message = "cloudsql.iam_authentication is mandatory and cannot be disabled."
  }

  validation {
    condition     = lookup(var.database_flags, "cloudsql.enable_pgaudit", "on") == "on"
    error_message = "cloudsql.enable_pgaudit is mandatory for security auditing and cannot be disabled."
  }

  validation {
    condition     = lookup(var.database_flags, "log_connections", "on") == "on" && lookup(var.database_flags, "log_disconnections", "on") == "on"
    error_message = "log_connections and log_disconnections are mandatory for security auditing and cannot be disabled."
  }

  validation {
    condition     = lower(trimspace(lookup(var.database_flags, "pgaudit.log", "ddl,role,write"))) != "none" && trimspace(lookup(var.database_flags, "pgaudit.log", "ddl,role,write")) != ""
    error_message = "pgaudit.log cannot be empty or set to \"none\"; audit logging must remain active."
  }
}

variable "databases" {
  description = "Map of logical PostgreSQL databases to create on the primary instance, keyed by database name."
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string, "en_US.UTF8")
    deletion_policy = optional(string, "DELETE")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.databases) : !contains(["postgres", "template0", "template1", "cloudsqladmin"], lower(k))])
    error_message = "System databases (postgres, template0, template1, cloudsqladmin) must not be specified in var.databases."
  }

  validation {
    condition     = alltrue([for v in values(var.databases) : contains(["DELETE", "ABANDON"], v.deletion_policy)])
    error_message = "Each database deletion_policy must be \"DELETE\" or \"ABANDON\"."
  }
}

variable "iam_users" {
  description = "Set of engineer Google identity emails (e.g., alice@example.com) to provision as CLOUD_IAM_USER database accounts."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", u)) && !endswith(u, ".gserviceaccount.com")])
    error_message = "Each entry in iam_users must be a valid user email address and must not be a service account (use iam_service_accounts for service accounts)."
  }
}

variable "iam_service_accounts" {
  description = "Set of full GCP service account emails (e.g., app@project.iam.gserviceaccount.com) for GKE/GCE workloads to provision as CLOUD_IAM_SERVICE_ACCOUNT database accounts. The .gserviceaccount.com suffix is stripped automatically for PostgreSQL usernames."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : can(regex("^[^@\\s]+@[^@\\s]+\\.gserviceaccount\\.com$", sa))])
    error_message = "Each entry in iam_service_accounts must be a full GCP service account email ending in .gserviceaccount.com."
  }
}

variable "iam_groups" {
  description = "Set of Google Group emails (e.g., dbas@example.com) to provision as CLOUD_IAM_GROUP database accounts."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for g in var.iam_groups : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", g)) && !endswith(g, ".gserviceaccount.com")])
    error_message = "Each entry in iam_groups must be a valid Google Group email address."
  }
}

variable "grant_iam_roles" {
  description = "When true, automatically grants instance-scoped roles/cloudsql.instanceUser and roles/cloudsql.client (using IAM conditions) to every identity in iam_users, iam_service_accounts, and iam_groups."
  type        = bool
  default     = true
}

variable "backup_configuration" {
  description = "Optional overrides for automated backup and Point-in-Time Recovery (PITR) settings. Automated backups and PITR are always enabled."
  type = object({
    start_time                     = optional(string, "02:00")
    location                       = optional(string, null)
    retained_backups               = optional(number, null)
    transaction_log_retention_days = optional(number, null)
  })
  default = {}

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_configuration.start_time))
    error_message = "backup_configuration.start_time must be in 24-hour HH:MM UTC format (e.g., \"02:00\")."
  }

  validation {
    condition     = var.backup_configuration.retained_backups == null || (var.backup_configuration.retained_backups >= 1 && var.backup_configuration.retained_backups <= 365 && floor(var.backup_configuration.retained_backups) == var.backup_configuration.retained_backups)
    error_message = "backup_configuration.retained_backups must be an integer between 1 and 365."
  }

  validation {
    condition     = var.backup_configuration.transaction_log_retention_days == null || (var.backup_configuration.transaction_log_retention_days >= 1 && var.backup_configuration.transaction_log_retention_days <= 35 && floor(var.backup_configuration.transaction_log_retention_days) == var.backup_configuration.transaction_log_retention_days)
    error_message = "backup_configuration.transaction_log_retention_days must be an integer between 1 and 35 (max 7 for ENTERPRISE, max 35 for ENTERPRISE_PLUS)."
  }
}

variable "maintenance_window" {
  description = "Optional overrides for the Cloud SQL maintenance window (UTC). Defaults to Sunday 03:00 UTC with update_track canary in dev and stable in staging/prod."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string, null)
  })
  default = {}

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day
    error_message = "maintenance_window.day must be an integer between 1 (Monday) and 7 (Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour
    error_message = "maintenance_window.hour must be an integer between 0 and 23 (UTC)."
  }

  validation {
    condition     = var.maintenance_window.update_track == null || contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be \"canary\", \"stable\", \"week5\", or null."
  }
}

variable "deny_maintenance_period" {
  description = "Optional maintenance blackout window during which Cloud SQL will not perform routine maintenance."
  type = object({
    start_date = string
    end_date   = string
    time       = string
  })
  default = null

  validation {
    condition     = var.deny_maintenance_period == null || (can(regex("^([0-9]{4}-)?(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$", var.deny_maintenance_period.start_date)) && can(regex("^([0-9]{4}-)?(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$", var.deny_maintenance_period.end_date)) && can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$", var.deny_maintenance_period.time)))
    error_message = "deny_maintenance_period dates must be YYYY-MM-DD or MM-DD and time must be HH:MM:SS (UTC)."
  }
}

variable "query_insights" {
  description = "Tuning parameters for Cloud SQL Query Insights. Query Insights, application tags, and client address recording are always enabled."
  type = object({
    query_string_length    = optional(number, 1024)
    query_plans_per_minute = optional(number, 5)
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

variable "data_cache_enabled" {
  description = "Enable Enterprise Plus local SSD data cache. Requires edition = \"ENTERPRISE_PLUS\"."
  type        = bool
  default     = false
}

variable "connector_enforcement" {
  description = "Whether all connections must use Cloud SQL Auth Proxy or Language Connectors (REQUIRED) or also allow direct TLS + IAM private IP connections (NOT_REQUIRED)."
  type        = string
  default     = "NOT_REQUIRED"

  validation {
    condition     = contains(["NOT_REQUIRED", "REQUIRED"], var.connector_enforcement)
    error_message = "connector_enforcement must be \"NOT_REQUIRED\" or \"REQUIRED\"."
  }
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS CryptoKey resource ID for Customer-Managed Encryption Keys (CMEK). Uses Google-managed encryption when null."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Optional name of a specific private services access IP range allocated by the network team. When null, Cloud SQL uses the default PSA peering range on the VPC."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Enable deletion protection in both OpenTofu state and the Cloud SQL API. Defaults to true in prod and false in dev/staging."
  type        = bool
  default     = null
}

variable "retain_backups_on_delete" {
  description = "Retain automated backups after instance deletion. Defaults to true in prod and false in dev/staging."
  type        = bool
  default     = null
}

variable "read_replicas" {
  description = "Optional map of read replicas to provision alongside the primary instance, keyed by a short replica suffix (instance name becomes <name>-<key>)."
  type = map(object({
    region                = optional(string, null)
    zone                  = optional(string, null)
    tier                  = optional(string, null)
    availability_type     = optional(string, "ZONAL")
    disk_type             = optional(string, null)
    disk_autoresize_limit = optional(number, null)
    database_flags        = optional(map(string), {})
    encryption_key_name   = optional(string, null)
    deletion_protection   = optional(bool, null)
    labels                = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.read_replicas) : can(regex("^[a-z][a-z0-9-]{0,30}$", k)) && !endswith(k, "-")])
    error_message = "Each read_replicas key must start with a lowercase letter, end with a letter or digit, contain only lowercase letters, digits, and hyphens, and be at most 31 characters long."
  }

  validation {
    condition     = alltrue([for v in values(var.read_replicas) : contains(["ZONAL", "REGIONAL"], v.availability_type)])
    error_message = "Each read replica availability_type must be \"ZONAL\" or \"REGIONAL\"."
  }

  validation {
    condition     = alltrue([for v in values(var.read_replicas) : v.disk_type == null || contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], v.disk_type)])
    error_message = "Each read replica disk_type must be \"PD_SSD\", \"PD_HDD\", \"HYPERDISK_BALANCED\", or null."
  }

  validation {
    condition = alltrue([
      for v in values(var.read_replicas) :
      lookup(v.database_flags, "cloudsql.iam_authentication", "on") == "on" &&
      lookup(v.database_flags, "cloudsql.enable_pgaudit", "on") == "on" &&
      lookup(v.database_flags, "log_connections", "on") == "on" &&
      lookup(v.database_flags, "log_disconnections", "on") == "on" &&
      lower(trimspace(lookup(v.database_flags, "pgaudit.log", "ddl,role,write"))) != "none"
    ])
    error_message = "Read replica database_flags cannot disable mandatory IAM authentication or security auditing flags."
  }
}

variable "labels" {
  description = "Additional GCP labels to apply to the instance and read replicas (e.g., team, service, cost_center). Standard governance labels (managed_by, environment, engine, role) are always applied."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "GCP label keys must match ^[a-z][a-z0-9_-]{0,62}$ and values must match ^[a-z0-9_-]{0,63}$."
  }
}
