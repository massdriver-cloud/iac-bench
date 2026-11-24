variable "instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,82}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must consist of lowercase letters, numbers, and hyphens, start with a letter, and be between 2 and 84 characters."
  }
}

variable "environment" {
  description = "Deployment environment (`dev`, `staging`, or `prod`). Determines the target VPC network (`apps-<environment>`) and environment-specific defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "GCP region for the Cloud SQL instance."
  type        = string
  default     = "us-central1"
}

variable "database_version" {
  description = "The PostgreSQL version to use for the Cloud SQL instance."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_(1[3-9]|[2-9][0-9])$", var.database_version))
    error_message = "database_version must be a supported PostgreSQL version (e.g., POSTGRES_14, POSTGRES_15, POSTGRES_16)."
  }
}

variable "edition" {
  description = "The Cloud SQL edition (`ENTERPRISE` or `ENTERPRISE_PLUS`)."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be either ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine tier for the Cloud SQL instance (e.g., `db-custom-2-7680` or `db-perf-optimized-N-2`)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "Availability type (`REGIONAL` for high availability or `ZONAL` for single zone). Defaults to `REGIONAL` in prod and `ZONAL` in dev/staging if null."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL, ZONAL, or null."
  }
}

variable "disk_size_gb" {
  description = "Initial disk size in GB. Storage auto-resize is always enabled."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "disk_size_gb must be between 10 and 65536."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum size in GB to which storage can auto-resize. 0 means no limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0
    error_message = "disk_autoresize_limit_gb must be 0 or a positive integer."
  }
}

variable "disk_type" {
  description = "Disk type for the Cloud SQL instance (`PD_SSD` or `PD_HDD`)."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "deletion_protection" {
  description = "Whether to enable Terraform and GCP deletion protection. Defaults to true in prod and false in dev/staging if null."
  type        = bool
  default     = null
}

variable "backup_configuration" {
  description = "Backup and point-in-time recovery settings."
  type = object({
    start_time                     = optional(string, "03:00")
    location                       = optional(string, null)
    point_in_time_recovery_enabled = optional(bool, true)
    transaction_log_retention_days = optional(number, 7)
    retained_backups               = optional(number, 30)
  })
  default = {}

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):00$", var.backup_configuration.start_time))
    error_message = "backup_configuration.start_time must be in HH:00 UTC format."
  }

  validation {
    condition     = var.backup_configuration.transaction_log_retention_days >= 1 && var.backup_configuration.transaction_log_retention_days <= 7
    error_message = "backup_configuration.transaction_log_retention_days must be between 1 and 7."
  }

  validation {
    condition     = var.backup_configuration.retained_backups >= 1 && var.backup_configuration.retained_backups <= 365
    error_message = "backup_configuration.retained_backups must be between 1 and 365."
  }
}

variable "maintenance_window" {
  description = "Maintenance window settings (day 1-7 Monday-Sunday, hour 0-23 UTC, update_track `canary` or `stable`)."
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
    error_message = "maintenance_window.update_track must be canary, stable, or week5."
  }
}

variable "insights_config" {
  description = "Query Insights configuration for performance monitoring and auditing."
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
}

variable "database_flags" {
  description = "Additional or override PostgreSQL database flags (map of flag name to value). Merged over the module's baseline security and audit flags (`cloudsql.iam_authentication` is always enforced as `on`)."
  type        = map(string)
  default     = {}

  validation {
    condition     = lookup(var.database_flags, "cloudsql.iam_authentication", "on") == "on"
    error_message = "cloudsql.iam_authentication must remain 'on' to comply with security policy requiring IAM database authentication."
  }
}

variable "databases" {
  description = "Map of application databases to create in the instance, keyed by database name."
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string, "en_US.UTF8")
    deletion_policy = optional(string, "DELETE")
  }))
  default = {}
}

variable "iam_users" {
  description = "Map of Google identities to grant IAM database authentication access, keyed by logical identifier. Use type `CLOUD_IAM_USER` for human engineers and `CLOUD_IAM_SERVICE_ACCOUNT` for workload service accounts (note: Cloud SQL requires service account emails without the `.gserviceaccount.com` suffix, which the module strips automatically)."
  type = map(object({
    email           = string
    type            = optional(string, "CLOUD_IAM_USER")
    deletion_policy = optional(string, "DELETE")
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, u in var.iam_users : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT", "CLOUD_IAM_GROUP"], u.type)
    ])
    error_message = "Each iam_users entry type must be CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT, or CLOUD_IAM_GROUP."
  }
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS key self_link for Customer-Managed Encryption Keys (CMEK)."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional user labels to apply to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}
