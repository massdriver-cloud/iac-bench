variable "instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance (1-98 characters, lowercase letters, numbers, and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be between 2 and 98 characters."
  }
}

variable "environment" {
  description = "Deployment environment ('dev', 'staging', or 'prod'). Selects the target VPC network (apps-dev, apps-staging, apps-prod) and establishes environment-appropriate availability and protection defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: 'dev', 'staging', 'prod'."
  }
}

variable "region" {
  description = "Google Cloud region in which to deploy the Cloud SQL instance."
  type        = string
  default     = "us-central1"
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL engine version (e.g., POSTGRES_15, POSTGRES_16, POSTGRES_17)."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a valid PostgreSQL version identifier starting with 'POSTGRES_' (e.g., POSTGRES_16)."
  }
}

variable "edition" {
  description = "Cloud SQL edition ('ENTERPRISE' or 'ENTERPRISE_PLUS')."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be either 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  }
}

variable "tier" {
  description = "Machine type tier for the Cloud SQL instance (e.g., db-custom-2-7680, db-perf-optimized-N-2)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "Availability configuration ('REGIONAL' for high availability or 'ZONAL' for single zone). Defaults to 'REGIONAL' in prod and 'ZONAL' in dev/staging if null."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be 'REGIONAL', 'ZONAL', or null."
  }
}

variable "disk_type" {
  description = "Storage disk type ('PD_SSD' or 'PD_HDD')."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be 'PD_SSD' or 'PD_HDD'."
  }
}

variable "disk_size_gb" {
  description = "Initial disk size in GB. Storage auto-resize is enabled to prevent outages."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "disk_size_gb must be between 10 and 65536."
  }
}

variable "disk_autoresize_limit" {
  description = "Maximum size in GB to which storage can automatically resize (0 means no limit)."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit >= 0
    error_message = "disk_autoresize_limit must be 0 (unlimited) or a positive integer."
  }
}

variable "deletion_protection" {
  description = "Whether to protect the instance from accidental deletion via Terraform or the GCP API. Defaults to true in prod and false in dev/staging if null."
  type        = bool
  default     = null
}

variable "backup_config" {
  description = "Backup and point-in-time recovery (PITR) settings."
  type = object({
    start_time                     = optional(string, "03:00")
    location                       = optional(string, null)
    point_in_time_recovery_enabled = optional(bool, true)
    transaction_log_retention_days = optional(number, 7)
    retained_backups               = optional(number, 14)
  })
  default = {}

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_config.start_time))
    error_message = "backup_config.start_time must be in HH:MM 24-hour UTC format."
  }

  validation {
    condition     = var.backup_config.transaction_log_retention_days >= 1 && var.backup_config.transaction_log_retention_days <= 7
    error_message = "backup_config.transaction_log_retention_days must be between 1 and 7."
  }

  validation {
    condition     = var.backup_config.retained_backups >= 1 && var.backup_config.retained_backups <= 365
    error_message = "backup_config.retained_backups must be between 1 and 365."
  }
}

variable "maintenance_window" {
  description = "Preferred weekly maintenance window (day 1-7 Monday-Sunday, hour 0-23 UTC, update_track 'canary' or 'stable')."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 4)
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7
    error_message = "maintenance_window.day must be between 1 (Monday) and 7 (Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.hour must be between 0 and 23."
  }

  validation {
    condition     = contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be 'canary', 'stable', or 'week5'."
  }
}

variable "insights_config" {
  description = "Query Insights settings for DBA performance diagnostics and auditing."
  type = object({
    query_insights_enabled  = optional(bool, true)
    query_string_length     = optional(number, 1024)
    record_application_tags = optional(bool, true)
    record_client_address   = optional(bool, true)
    query_plans_per_minute  = optional(number, 5)
  })
  default = {}

  validation {
    condition     = var.insights_config.query_string_length >= 256 && var.insights_config.query_string_length <= 4500
    error_message = "insights_config.query_string_length must be between 256 and 4500."
  }

  validation {
    condition     = var.insights_config.query_plans_per_minute >= 0 && var.insights_config.query_plans_per_minute <= 20
    error_message = "insights_config.query_plans_per_minute must be between 0 and 20."
  }
}

variable "database_flags" {
  description = "Map of additional or override PostgreSQL database flags (flag name => value) for DBA tuning. Core security and audit flags are automatically enabled and cannot have IAM auth disabled."
  type        = map(string)
  default     = {}

  validation {
    condition     = lookup(var.database_flags, "cloudsql.iam_authentication", "on") == "on"
    error_message = "cloudsql.iam_authentication must remain 'on' to enforce Google identity database access and security auditing."
  }
}

variable "databases" {
  description = "Map of databases to create on the instance, keyed by database name."
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string, "en_US.UTF8")
    deletion_policy = optional(string, "DELETE")
  }))
  default = {}
}

variable "iam_users" {
  description = "Map of Google IAM principals to provision as Cloud SQL IAM database users. Key is an arbitrary identifier or principal email; type must be 'CLOUD_IAM_USER', 'CLOUD_IAM_SERVICE_ACCOUNT', or 'CLOUD_IAM_GROUP'."
  type = map(object({
    name = string
    type = optional(string, "CLOUD_IAM_USER")
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, u in var.iam_users : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT", "CLOUD_IAM_GROUP"], u.type)
    ])
    error_message = "Each entry in iam_users must have type 'CLOUD_IAM_USER', 'CLOUD_IAM_SERVICE_ACCOUNT', or 'CLOUD_IAM_GROUP'."
  }
}

variable "kms_key_name" {
  description = "Optional Cloud KMS crypto key self-link for Customer-Managed Encryption Keys (CMEK)."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional user labels to attach to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}
