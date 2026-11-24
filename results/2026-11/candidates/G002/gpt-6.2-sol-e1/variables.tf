variable "environment" {
  description = "Environment; selects the existing apps-<environment> VPC in the Google provider's project."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "instance_name" {
  description = "Cloud SQL instance ID, unique within the project. Choose a stable name."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$|^[a-z]$", var.instance_name))
    error_message = "instance_name must be 1–98 characters, start with a lowercase letter, end with a letter or digit, and use only lowercase letters, digits, or hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for the instance. Choose a region near the applications."
  type        = string
  nullable    = false
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version, such as POSTGRES_16. Check edition and region compatibility before a major upgrade."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^POSTGRES_[1-9][0-9]+$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL major-version identifier, for example POSTGRES_16."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier, compatible with the selected edition, version, and region."
  type        = string
  nullable    = false
}

variable "edition" {
  description = "Cloud SQL edition. Set explicitly so a PostgreSQL upgrade does not silently select a different edition."
  type        = string
  default     = "ENTERPRISE"
  nullable    = false

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "REGIONAL for high availability, or ZONAL for a single zone. If omitted, production is REGIONAL and other environments are ZONAL."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null ? true : contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL when set."
  }
}

variable "initial_disk_size_gb" {
  description = "Initial SSD capacity in GB. Cloud SQL automatically grows it; later changes to this input do not resize the disk."
  type        = number
  default     = 20
  nullable    = false

  validation {
    condition     = var.initial_disk_size_gb >= 10 && floor(var.initial_disk_size_gb) == var.initial_disk_size_gb
    error_message = "initial_disk_size_gb must be a whole number of at least 10 GB."
  }
}

variable "backup" {
  description = "Daily backup start time (UTC), number of backups to retain, and PITR log retention (days). Backups and PITR are always enabled."
  type = object({
    start_time                     = optional(string, "03:00")
    retained_backups               = optional(number, 14)
    transaction_log_retention_days = optional(number, 7)
  })
  default  = {}
  nullable = false

  validation {
    condition = (
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup.start_time)) &&
      var.backup.retained_backups >= 1 && var.backup.retained_backups <= 365 &&
      floor(var.backup.retained_backups) == var.backup.retained_backups &&
      var.backup.transaction_log_retention_days >= 1 && var.backup.transaction_log_retention_days <= 35 &&
      floor(var.backup.transaction_log_retention_days) == var.backup.transaction_log_retention_days &&
      var.backup.retained_backups > var.backup.transaction_log_retention_days
    )
    error_message = "Supply a UTC HH:MM start time, 1–365 retained backups, and 1–35 PITR days. The backup count must exceed the PITR days; Enterprise permits at most 7 PITR days."
  }
}

variable "maintenance_window" {
  description = "Optional maintenance window in UTC: day 1 (Monday) through 7 (Sunday), hour 0–23, and update track."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string, "stable")
  })
  default = null

  validation {
    condition = var.maintenance_window == null ? true : (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour &&
      contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    )
    error_message = "Use an integer day 1–7, an integer UTC hour 0–23, and update_track canary, stable, or week5."
  }
}

variable "database_flags" {
  description = "Additional Cloud SQL PostgreSQL flags as string values. IAM authentication and connection logging are managed by the module."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for name, value in var.database_flags : !contains(["cloudsql.iam_authentication", "log_connections", "log_disconnections"], name) && value != null])
    error_message = "Do not supply module-managed flags (cloudsql.iam_authentication, log_connections, log_disconnections) or null flag values."
  }
}

variable "databases" {
  description = "Optional databases keyed by name. PostgreSQL defaults apply if charset and collation are omitted."
  type = map(object({
    charset   = optional(string)
    collation = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name, config in var.databases : config != null && length(name) > 0 && !contains(["postgres", "template0", "template1", "cloudsqladmin"], lower(name))])
    error_message = "Database definitions must not be null or use an empty or reserved database name."
  }
}

variable "iam_database_users" {
  description = "Database logins keyed by full lowercase Google identity email. Values: CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT, or CLOUD_IAM_GROUP. Use existing identities only."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for email, kind in var.iam_database_users :
      can(regex("^[^@[:space:]]+@[^@[:space:]]+$", email)) && email == lower(email) &&
      contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT", "CLOUD_IAM_GROUP"], coalesce(kind, "invalid")) &&
      ((kind == "CLOUD_IAM_SERVICE_ACCOUNT") == endswith(email, ".gserviceaccount.com")) &&
      length(trimsuffix(email, kind == "CLOUD_IAM_SERVICE_ACCOUNT" ? ".gserviceaccount.com" : "")) <= 63
    ])
    error_message = "Supply full lowercase IAM identity emails with a matching Cloud SQL IAM user type; PostgreSQL login names must fit within 63 characters after service account suffix removal."
  }
}

variable "labels" {
  description = "Additional Cloud SQL labels. The module owns the environment label."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = !contains(keys(var.labels), "environment")
    error_message = "The environment label is set by the module."
  }
}
