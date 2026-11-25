variable "name" {
  description = "Base name for the Cloud SQL PostgreSQL instance (e.g., 'orders', 'billing'). The environment suffix is appended automatically."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,60}[a-z0-9]$", var.name))
    error_message = "Instance name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, end with a letter or number, and be 3-62 characters long."
  }
}

variable "environment" {
  description = "Deployment environment. Determines the target VPC network (apps-dev, apps-staging, or apps-prod) and default availability/protection posture."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "GCP region in which to deploy the Cloud SQL instance."
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region identifier (e.g., us-central1)."
  }
}

variable "database_version" {
  description = "PostgreSQL engine version for the Cloud SQL instance."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "Supported PostgreSQL versions are POSTGRES_14, POSTGRES_15, POSTGRES_16, and POSTGRES_17."
  }
}

variable "edition" {
  description = "Cloud SQL edition (ENTERPRISE or ENTERPRISE_PLUS)."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "Edition must be either ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine type tier for the primary instance (e.g., db-custom-2-7680, db-perf-optimized-N-2)."
  type        = string
  default     = "db-custom-2-7680"

  validation {
    condition     = can(regex("^db-(custom-[0-9]+-[0-9]+|perf-optimized-N-[0-9]+|standard-[0-9]+|highmem-[0-9]+)$", var.tier))
    error_message = "Tier must be a dedicated-core Cloud SQL machine type (e.g., db-custom-<vcpu>-<ram_mb> or db-perf-optimized-N-<vcpu>). Shared-core micro/small tiers are not permitted."
  }
}

variable "availability_type" {
  description = "Availability type (REGIONAL for high availability with automatic failover, ZONAL for single-zone). Defaults to REGIONAL in prod and ZONAL in dev/staging when null."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL, ZONAL, or null."
  }
}

variable "disk_size_gb" {
  description = "Initial storage size in GB. Storage autoresize is enabled by default."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be an integer between 10 and 65536."
  }
}

variable "disk_type" {
  description = "Storage disk type for the Cloud SQL instance."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum size in GB to which storage can auto-resize (0 means no limit)."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0 && var.disk_autoresize_limit_gb <= 65536
    error_message = "disk_autoresize_limit_gb must be between 0 (unlimited) and 65536."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL database flags owned by the DBA team (merged with mandatory baseline security and auditing flags; mandatory flags cannot be disabled)."
  type        = map(string)
  default     = {}

  validation {
    condition = !anytrue([
      for k, v in var.database_flags :
      (k == "cloudsql.iam_authentication" && v != "on") ||
      (k == "cloudsql.enable_pgaudit" && v != "on")
    ])
    error_message = "Mandatory security flags cloudsql.iam_authentication and cloudsql.enable_pgaudit cannot be overridden to off."
  }
}

variable "databases" {
  description = "Map of additional logical databases to create on the instance, keyed by database name."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "iam_users" {
  description = "Map of IAM identities granted database login access, keyed by display/logical key. Each entry specifies the identity email and account type (CLOUD_IAM_USER for human engineers or CLOUD_IAM_SERVICE_ACCOUNT for workload service accounts, or CLOUD_IAM_GROUP for IAM groups)."
  type = map(object({
    email = string
    type  = optional(string, "CLOUD_IAM_USER")
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, u in var.iam_users :
      contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT", "CLOUD_IAM_GROUP"], u.type) &&
      can(regex("^[^@]+@[^@]+\\.[^@]+$", u.email))
    ])
    error_message = "Each entry in iam_users must have a valid email and a type of CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT, or CLOUD_IAM_GROUP."
  }
}

variable "backup_configuration" {
  description = "Backup and point-in-time recovery configuration."
  type = object({
    start_time                     = optional(string, "03:00")
    location                       = optional(string, null)
    point_in_time_recovery_enabled = optional(bool, true)
    transaction_log_retention_days = optional(number, 7)
    retained_backups               = optional(number, 14)
  })
  default = {}

  validation {
    condition = (
      can(regex("^([01][0-9]|2[0-3]):00$", var.backup_configuration.start_time)) &&
      var.backup_configuration.transaction_log_retention_days >= 1 &&
      var.backup_configuration.transaction_log_retention_days <= 7 &&
      var.backup_configuration.retained_backups >= 1 &&
      var.backup_configuration.retained_backups <= 365
    )
    error_message = "backup_configuration requires start_time in HH:00 format, transaction_log_retention_days between 1 and 7, and retained_backups between 1 and 365."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance window configuration (day 1-7 Monday-Sunday, hour 0-23 UTC)."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 4)
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 &&
      contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    )
    error_message = "maintenance_window requires day 1-7, hour 0-23, and update_track in [canary, stable, week5]."
  }
}

variable "query_insights_config" {
  description = "Query Insights monitoring configuration for DBA performance analysis and audit traceability."
  type = object({
    query_plans_per_minute  = optional(number, 5)
    query_string_length     = optional(number, 1024)
    record_application_tags = optional(bool, true)
    record_client_address   = optional(bool, true)
  })
  default = {}

  validation {
    condition = (
      var.query_insights_config.query_plans_per_minute >= 0 &&
      var.query_insights_config.query_plans_per_minute <= 20 &&
      var.query_insights_config.query_string_length >= 256 &&
      var.query_insights_config.query_string_length <= 4500
    )
    error_message = "query_insights_config requires query_plans_per_minute between 0 and 20, and query_string_length between 256 and 4500."
  }
}

variable "read_replicas" {
  description = "Map of read replica instances to create, keyed by replica suffix."
  type = map(object({
    region            = optional(string, null)
    tier              = optional(string, null)
    availability_type = optional(string, "ZONAL")
    disk_size_gb      = optional(number, null)
    database_flags    = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, r in var.read_replicas :
      can(regex("^[a-z0-9-]+$", k)) &&
      contains(["ZONAL", "REGIONAL"], r.availability_type)
    ])
    error_message = "Read replica keys must be lowercase alphanumeric/hyphens and availability_type must be ZONAL or REGIONAL."
  }
}

variable "deletion_protection" {
  description = "Whether Terraform and GCP deletion protection are enabled. Defaults to true in prod and false in dev/staging when null."
  type        = bool
  default     = null
}

variable "kms_key_name" {
  description = "Optional Cloud KMS CMEK key self_link/ID for customer-managed encryption at rest."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional user labels to apply to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}
