variable "name" {
  description = "The name of the Cloud SQL PostgreSQL database instance."
  type        = string
}

variable "environment" {
  description = "The environment for the instance. Accepted values: 'apps-dev', 'apps-staging', 'apps-prod' (or 'dev', 'staging', 'prod'). Determines VPC network and operational defaults."
  type        = string
  validation {
    condition     = contains(["apps-dev", "apps-staging", "apps-prod", "dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: apps-dev, apps-staging, apps-prod, dev, staging, prod."
  }
}

variable "database_version" {
  description = "The PostgreSQL database engine version (e.g. POSTGRES_14, POSTGRES_15, POSTGRES_16)."
  type        = string
  default     = "POSTGRES_15"
  validation {
    condition     = startswith(var.database_version, "POSTGRES_")
    error_message = "database_version must start with 'POSTGRES_'."
  }
}

variable "tier" {
  description = "The machine tier (vCPU and memory) for the Cloud SQL instance (e.g. 'db-custom-2-7680')."
  type        = string
  default     = "db-custom-2-7680"
}

variable "edition" {
  description = "The Cloud SQL edition: 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  type        = string
  default     = "ENTERPRISE"
  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be either 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  }
}

variable "availability_type" {
  description = "High Availability configuration: 'REGIONAL' (HA with automatic failover) or 'ZONAL' (single zone). If null, defaults to 'REGIONAL' in production and 'ZONAL' in dev/staging."
  type        = string
  default     = null
  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, "REGIONAL"))
    error_message = "availability_type must be either 'REGIONAL' or 'ZONAL'."
  }
}

variable "disk_size" {
  description = "The initial disk size in GB."
  type        = number
  default     = 20
}

variable "disk_type" {
  description = "The disk type for the instance ('PD_SSD' or 'PD_HDD')."
  type        = string
  default     = "PD_SSD"
  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be either 'PD_SSD' or 'PD_HDD'."
  }
}

variable "disk_autoresize" {
  description = "Whether to automatically increase storage capacity as disk fills up."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "Maximum storage capacity limit in GB for auto-resizing (0 = unlimited)."
  type        = number
  default     = 0
}

variable "activation_policy" {
  description = "The activation policy for the instance ('ALWAYS', 'NEVER', 'ON_DEMAND')."
  type        = string
  default     = "ALWAYS"
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection. If null, defaults to true in production and false in dev/staging."
  type        = bool
  default     = null
}

variable "project_id" {
  description = "Google Cloud Project ID. If null, provider project is used."
  type        = string
  default     = null
}

variable "region" {
  description = "Google Cloud region for the instance. If null, provider region is used."
  type        = string
  default     = null
}

variable "zone" {
  description = "Specific compute zone for zonal deployment (e.g. 'us-central1-a')."
  type        = string
  default     = null
}

variable "network" {
  description = "Optional VPC network name or self link. If null, resolved automatically from var.environment."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of the allocated PSA IP range for the instance, if specific range is required."
  type        = string
  default     = null
}

variable "ipv4_enabled" {
  description = "Whether public IPv4 is enabled. Defaults to false (private services access only)."
  type        = bool
  default     = false
}

variable "ssl_mode" {
  description = "SSL mode for client connections ('ENCRYPTED_ONLY', 'TRUSTED_CLIENT_CERTIFICATE_REQUIRED', or 'ALLOW_UNENCRYPTED_AND_ENCRYPTED')."
  type        = string
  default     = "ENCRYPTED_ONLY"
}

variable "backup_enabled" {
  description = "Whether automated daily backups are enabled."
  type        = bool
  default     = true
}

variable "point_in_time_recovery_enabled" {
  description = "Whether point-in-time recovery (WAL archive) is enabled."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "HH:MM format start time for daily backups in UTC."
  type        = string
  default     = "03:00"
}

variable "retained_backups" {
  description = "Number of daily backups to retain. If null, defaults to 30 for production and 7 for dev/staging."
  type        = number
  default     = null
}

variable "transaction_log_retention_days" {
  description = "Number of days of transaction logs (WAL) to retain for point-in-time recovery."
  type        = number
  default     = 7
}

variable "maintenance_window_day" {
  description = "Day of week (1-7, 1=Monday, 7=Sunday) for maintenance window."
  type        = number
  default     = 7
}

variable "maintenance_window_hour" {
  description = "Hour of day (0-23 UTC) for maintenance window."
  type        = number
  default     = 4
}

variable "maintenance_window_update_track" {
  description = "Update track for maintenance: 'stable', 'canary', or 'preview'."
  type        = string
  default     = "stable"
}

variable "query_insights_enabled" {
  description = "Whether to enable Query Insights for query performance monitoring."
  type        = bool
  default     = true
}

variable "query_string_length" {
  description = "Query string length in bytes stored in Query Insights (256-4500)."
  type        = number
  default     = 1024
}

variable "record_application_tags" {
  description = "Whether Query Insights records application tags."
  type        = bool
  default     = true
}

variable "record_client_address" {
  description = "Whether Query Insights records client IP address."
  type        = bool
  default     = true
}

variable "query_plans_per_minute" {
  description = "Number of query plans to sample per minute for Query Insights (0-20)."
  type        = number
  default     = 5
}

variable "database_flags" {
  description = "List of custom database flags to assign to the instance. Mandatory flag 'cloudsql.iam_authentication' is always enforced."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "databases" {
  description = "List of databases to create on the instance."
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = []
}

variable "iam_users" {
  description = "List of engineer Google account email addresses for IAM database authentication."
  type        = list(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "List of workload service account email addresses for IAM database authentication."
  type        = list(string)
  default     = []
}

variable "users" {
  description = "List of additional database users to create, with name, type (BUILT_IN, CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT), and optional password."
  type = list(object({
    name     = string
    type     = optional(string, "BUILT_IN")
    password = optional(string, null)
  }))
  default = []
}

variable "labels" {
  description = "Key/value label pairs to assign to the instance."
  type        = map(string)
  default     = {}
}
