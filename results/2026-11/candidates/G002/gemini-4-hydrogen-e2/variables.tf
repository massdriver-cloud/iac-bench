variable "name" {
  description = "Logical name of the PostgreSQL instance (e.g. 'orders', 'billing'). Combined with environment to form '<name>-<environment>'."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,39}$", var.name)) && !endswith(var.name, "-")
    error_message = "name must be 2-40 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and not end with a hyphen."
  }
}

variable "environment" {
  description = "Target environment. Determines the VPC network ('apps-<environment>') and environment-specific defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "GCP region where the primary Cloud SQL instance is deployed."
  type        = string
  default     = "us-central1"
}

variable "database_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "database_version must be a supported PostgreSQL version: POSTGRES_13, POSTGRES_14, POSTGRES_15, POSTGRES_16, or POSTGRES_17."
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

variable "tier" {
  description = "Cloud SQL machine tier (e.g. 'db-custom-2-8192'). If null, uses environment default (dev: db-custom-1-3840, staging: db-custom-2-8192, prod: db-custom-4-16384)."
  type        = string
  default     = null
}

variable "availability_type" {
  description = "Availability type ('REGIONAL' for HA or 'ZONAL'). If null, defaults to REGIONAL in prod and ZONAL in dev/staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be either REGIONAL or ZONAL."
  }
}

variable "disk_size" {
  description = "Initial storage size in GB (minimum 10). If null, uses environment default (dev: 20, staging: 50, prod: 100)."
  type        = number
  default     = null

  validation {
    condition     = var.disk_size == null || var.disk_size >= 10
    error_message = "disk_size must be at least 10 GB."
  }
}

variable "disk_autoresize_limit" {
  description = "Maximum storage size in GB for automatic disk growth (0 means unlimited)."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit >= 0
    error_message = "disk_autoresize_limit must be 0 (unlimited) or a positive number of GB."
  }
}

variable "allocated_ip_range" {
  description = "Optional name of an existing private services access IP allocation range in the VPC network."
  type        = string
  default     = null
}

variable "require_client_certificate" {
  description = "When true, sets ssl_mode to TRUSTED_CLIENT_CERTIFICATE_REQUIRED; when false (default), enforces ENCRYPTED_ONLY."
  type        = bool
  default     = false
}

variable "enforce_cloud_sql_connector" {
  description = "When true, requires all connections to go through Cloud SQL Auth Proxy or Language Connectors (connector_enforcement = REQUIRED)."
  type        = bool
  default     = false
}

variable "databases" {
  description = "Map of PostgreSQL databases to create on the instance, keyed by database name."
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string, "en_US.UTF8")
    deletion_policy = optional(string, "ABANDON")
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, db in var.databases : contains(["ABANDON", "DELETE"], db.deletion_policy)
    ])
    error_message = "Each database deletion_policy must be either ABANDON or DELETE."
  }
}

variable "database_flags" {
  description = "PostgreSQL database flags tuned by the DBA team. Security and audit flags (iam_authentication, pgaudit, connection/checkpoint/lock logging) are platform-managed and cannot be overridden."
  type        = map(string)
  default     = {}

  validation {
    condition = length(setintersection(keys(var.database_flags), [
      "cloudsql.iam_authentication",
      "cloudsql.enable_pgaudit",
      "log_connections",
      "log_disconnections",
      "log_checkpoints",
      "log_lock_waits",
    ])) == 0
    error_message = "Platform-managed security and audit flags (cloudsql.iam_authentication, cloudsql.enable_pgaudit, log_connections, log_disconnections, log_checkpoints, log_lock_waits) are enforced automatically and cannot be set in database_flags."
  }
}

variable "backup_configuration" {
  description = "Backup schedule and retention overrides. Automated backups and PITR are always enabled."
  type = object({
    start_time                     = optional(string, "03:00")
    location                       = optional(string)
    retained_backups               = optional(number)
    transaction_log_retention_days = optional(number)
  })
  default = {}

  validation {
    condition     = var.backup_configuration.start_time == null || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_configuration.start_time))
    error_message = "backup_configuration.start_time must be in HH:MM 24-hour UTC format (e.g. '03:00')."
  }

  validation {
    condition     = var.backup_configuration.retained_backups == null || var.backup_configuration.retained_backups >= 7
    error_message = "backup_configuration.retained_backups must be at least 7 backups."
  }

  validation {
    condition     = var.backup_configuration.transaction_log_retention_days == null || (var.backup_configuration.transaction_log_retention_days >= 1 && var.backup_configuration.transaction_log_retention_days <= 35)
    error_message = "backup_configuration.transaction_log_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Preferred weekly maintenance window (UTC) and update track for the primary instance."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string)
  })
  default = {}

  validation {
    condition     = var.maintenance_window.day == null || (var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7)
    error_message = "maintenance_window.day must be between 1 (Monday) and 7 (Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour == null || (var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23)
    error_message = "maintenance_window.hour must be between 0 and 23."
  }

  validation {
    condition     = var.maintenance_window.update_track == null || contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be one of: canary, stable, week5."
  }
}

variable "iam_users" {
  description = "Set of Google user email addresses granted IAM database authentication and instance-scoped Cloud SQL access."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", u))])
    error_message = "Each entry in iam_users must be a valid email address."
  }
}

variable "iam_service_accounts" {
  description = "Set of Google service account emails (workloads on GKE/GCE) granted IAM database authentication and instance-scoped Cloud SQL access."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : can(regex("^[^@\\s]+@[^@\\s]+\\.iam\\.gserviceaccount\\.com$", sa))])
    error_message = "Each entry in iam_service_accounts must be a full GCP service account email ending in '.iam.gserviceaccount.com'."
  }
}

variable "iam_groups" {
  description = "Set of Google Group email addresses granted IAM database authentication and instance-scoped Cloud SQL access."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for g in var.iam_groups : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", g))])
    error_message = "Each entry in iam_groups must be a valid Google Group email address."
  }
}

variable "iam_user_deletion_policy" {
  description = "Deletion policy for google_sql_user IAM resources ('ABANDON' prevents drop failures when roles own DB objects)."
  type        = string
  default     = "ABANDON"

  validation {
    condition     = contains(["ABANDON", "DELETE"], var.iam_user_deletion_policy)
    error_message = "iam_user_deletion_policy must be either ABANDON or DELETE."
  }
}

variable "read_replicas" {
  description = "Optional map of read replicas to create for this primary instance, keyed by replica suffix."
  type = map(object({
    region                = optional(string)
    tier                  = optional(string)
    availability_type     = optional(string, "ZONAL")
    disk_size             = optional(number)
    disk_autoresize_limit = optional(number)
    database_flags        = optional(map(string), {})
    maintenance_window = optional(object({
      day          = optional(number, 7)
      hour         = optional(number, 4)
      update_track = optional(string)
    }), {})
    deletion_protection = optional(bool)
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, r in var.read_replicas : contains(["REGIONAL", "ZONAL"], r.availability_type)
    ])
    error_message = "Each read replica availability_type must be either REGIONAL or ZONAL."
  }

  validation {
    condition = alltrue([
      for _, r in var.read_replicas : length(setintersection(keys(r.database_flags), [
        "cloudsql.iam_authentication",
        "cloudsql.enable_pgaudit",
        "log_connections",
        "log_disconnections",
        "log_checkpoints",
        "log_lock_waits",
      ])) == 0
    ])
    error_message = "Platform-managed security and audit flags cannot be overridden in read replica database_flags."
  }
}

variable "deletion_protection" {
  description = "Whether Terraform/OpenTofu and Cloud SQL API deletion protection are enabled on the primary instance."
  type        = bool
  default     = true
}

variable "enable_monitoring_alerts" {
  description = "Whether to provision standard Cloud Monitoring alert policies (CPU, memory, disk, availability) for the primary instance."
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of Cloud Monitoring notification channel resource names to attach to database alerts."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Additional GCP resource labels merged with standard module labels."
  type        = map(string)
  default     = {}
}
