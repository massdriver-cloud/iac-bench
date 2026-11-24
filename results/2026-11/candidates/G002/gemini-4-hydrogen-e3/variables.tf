variable "name" {
  description = "Logical name for the Cloud SQL PostgreSQL instance (combined with environment as '<name>-<environment>')."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,60}[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens (2-62 chars)."
  }
}

variable "environment" {
  description = "Target environment ('dev', 'staging', or 'prod'). Determines the private VPC network ('apps-<environment>') and environment-tier defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: 'dev', 'staging', 'prod'."
  }
}

variable "region" {
  description = "GCP region where the primary Cloud SQL instance is deployed."
  type        = string
}

variable "zone" {
  description = "Optional preferred GCP zone for the primary instance (e.g., to co-locate with Compute Engine or zonal GKE workloads)."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Optional preferred secondary GCP zone for REGIONAL high-availability failover."
  type        = string
  default     = null
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "database_version must be a supported PostgreSQL version (POSTGRES_13 through POSTGRES_17)."
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
  description = "Cloud SQL machine tier (e.g., 'db-custom-2-8192'). Defaults to 'db-custom-2-8192' in prod and 'db-custom-1-3840' in dev/staging."
  type        = string
  default     = null
}

variable "availability_type" {
  description = "High availability mode ('REGIONAL' or 'ZONAL'). Defaults to 'REGIONAL' in prod and 'ZONAL' in dev/staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be 'ZONAL' or 'REGIONAL'."
  }
}

variable "disk_size" {
  description = "Initial data disk size in GB. Defaults to 100 GB in prod and 20 GB in dev/staging."
  type        = number
  default     = null

  validation {
    condition     = var.disk_size == null || var.disk_size >= 10
    error_message = "disk_size must be at least 10 GB."
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

variable "disk_autoresize" {
  description = "Whether Cloud SQL automatically increases storage capacity when free space runs low."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "Maximum storage size in GB for disk autoresize (0 means unlimited)."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit >= 0
    error_message = "disk_autoresize_limit must be 0 or greater."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental instance deletion via OpenTofu and Cloud SQL API. Defaults to true in staging/prod and false in dev."
  type        = bool
  default     = null
}

variable "database_flags" {
  description = "DBA-managed PostgreSQL database flags (e.g., max_connections, work_mem, shared_buffers). Security and audit baseline flags remain enforced."
  type        = map(string)
  default     = {}
}

variable "pgaudit_log" {
  description = "pgaudit.log setting controlling audited statement classes (e.g., 'ddl,role', 'write,ddl,role', 'all')."
  type        = string
  default     = "ddl,role"
}

variable "databases" {
  description = "Map of application PostgreSQL databases to create on the primary instance."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "iam_users" {
  description = "Set of Google user identities (email addresses) granted IAM authentication access to the instance."
  type        = set(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "Set of Google service account emails (for GKE/GCE workloads) granted IAM authentication access to the instance."
  type        = set(string)
  default     = []
}

variable "iam_groups" {
  description = "Set of Google Group email addresses granted IAM authentication access to the instance."
  type        = set(string)
  default     = []
}

variable "manage_iam_bindings" {
  description = "Whether to grant conditional project IAM roles (roles/cloudsql.instanceUser and roles/cloudsql.client) scoped to this instance for declared IAM identities."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Start time (HH:MM in UTC) for the daily automated backup window."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be in HH:MM 24-hour UTC format (e.g., '03:00')."
  }
}

variable "retained_backups" {
  description = "Number of automated backups to retain. Defaults to 14 in prod and 7 in dev/staging."
  type        = number
  default     = null

  validation {
    condition     = var.retained_backups == null || (var.retained_backups >= 1 && var.retained_backups <= 365)
    error_message = "retained_backups must be between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Number of days of transaction logs retained for point-in-time recovery (1-7 for ENTERPRISE, 1-35 for ENTERPRISE_PLUS)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window_day" {
  description = "Day of week (1=Monday .. 7=Sunday) for the Cloud SQL maintenance window."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "maintenance_window_day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_window_hour" {
  description = "Hour of day (0-23 UTC) for the Cloud SQL maintenance window."
  type        = number
  default     = 4

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "maintenance_window_hour must be between 0 and 23."
  }
}

variable "maintenance_window_update_track" {
  description = "Maintenance update track ('canary', 'stable', or 'week5'). Defaults to 'stable' in staging/prod and 'canary' in dev."
  type        = string
  default     = null

  validation {
    condition     = var.maintenance_window_update_track == null || contains(["canary", "stable", "week5"], var.maintenance_window_update_track)
    error_message = "maintenance_window_update_track must be 'canary', 'stable', or 'week5'."
  }
}

variable "insights_query_plans_per_minute" {
  description = "Maximum number of query execution plans recorded per minute by Query Insights."
  type        = number
  default     = 5

  validation {
    condition     = var.insights_query_plans_per_minute >= 0 && var.insights_query_plans_per_minute <= 20
    error_message = "insights_query_plans_per_minute must be between 0 and 20."
  }
}

variable "insights_query_string_length" {
  description = "Maximum query string length in bytes stored by Query Insights."
  type        = number
  default     = 4096

  validation {
    condition     = var.insights_query_string_length >= 256 && var.insights_query_string_length <= 4500
    error_message = "insights_query_string_length must be between 256 and 4500."
  }
}

variable "data_cache_enabled" {
  description = "Enable Cloud SQL Data Cache (only applicable when edition is 'ENTERPRISE_PLUS')."
  type        = bool
  default     = false
}

variable "cmek_key_name" {
  description = "Optional Cloud KMS CryptoKey resource ID for customer-managed encryption."
  type        = string
  default     = null
}

variable "read_replicas" {
  description = "Optional map of read replicas to deploy alongside the primary instance. Replicas inherit private networking, SSL, IAM auth, insights, and audit logging."
  type = map(object({
    region            = optional(string)
    zone              = optional(string)
    tier              = optional(string)
    availability_type = optional(string, "ZONAL")
    disk_size         = optional(number)
    database_flags    = optional(map(string), {})
  }))
  default = {}
}

variable "labels" {
  description = "Additional GCP resource labels merged with standard module labels."
  type        = map(string)
  default     = {}
}
