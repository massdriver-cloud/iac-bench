########################################
# Where the instance lives
########################################

variable "project_id" {
  description = "GCP project that will own the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the instance. Must be a region in which the environment's VPC has private services access configured."
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Deployment environment. Selects the VPC the instance attaches to (apps-<environment>) and the environment-specific defaults (HA, backup retention)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "name" {
  description = "Name of the Cloud SQL instance. Lowercase letters, digits and hyphens; must start with a letter. Note that Cloud SQL reserves instance names for about a week after deletion."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}$", var.name))
    error_message = "name must start with a letter and contain only lowercase letters, digits and hyphens (max 97 chars)."
  }
}

########################################
# Networking (private IP only)
########################################

variable "network_project_id" {
  description = "Project that hosts the apps-<environment> VPC. Defaults to project_id; set this when the VPC is a Shared VPC in a host project."
  type        = string
  default     = null
}

variable "network_name" {
  description = "Override the VPC network name. Defaults to apps-<environment>. Only use this for an exceptional case the network team has agreed to."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of the allocated IP range (private services access) to pick the private IP from. Leave null to let Cloud SQL choose from the ranges the network team peered."
  type        = string
  default     = null
}

variable "enable_private_path_for_google_cloud_services" {
  description = "Allow Google-managed services (e.g. BigQuery federated queries) to reach the instance over its private IP."
  type        = bool
  default     = false
}

variable "require_client_certificates" {
  description = "When true, clients must present a Cloud SQL client certificate in addition to using TLS (TRUSTED_CLIENT_CERTIFICATE_REQUIRED). TLS is always mandatory regardless of this setting."
  type        = bool
  default     = false
}

########################################
# Engine / sizing — the DBA's calls
########################################

variable "database_version" {
  description = "PostgreSQL major version, as a Cloud SQL version string (e.g. POSTGRES_16). Only PostgreSQL versions are accepted."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a PostgreSQL version such as POSTGRES_16."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS. ENTERPRISE_PLUS requires a db-perf-optimized-N-* tier."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-8192 (2 vCPU, 8 GiB) or db-perf-optimized-N-4 for ENTERPRISE_PLUS."
  type        = string
  default     = "db-custom-2-8192"
}

variable "availability_type" {
  description = "REGIONAL (HA, synchronous standby in another zone) or ZONAL. Defaults to REGIONAL in prod and ZONAL elsewhere."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, "REGIONAL"))
    error_message = "availability_type must be REGIONAL or ZONAL."
  }
}

variable "disk_type" {
  description = "Disk type: PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GB. The disk auto-grows; this value is only the starting point and is not shrunk by later changes."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic disk growth in GB. 0 means no limit."
  type        = number
  default     = 0
}

variable "database_flags" {
  description = "PostgreSQL flags to set on the instance (name => value). Flags the module enforces for every instance (IAM authentication, connection logging) cannot be overridden here."
  type        = map(string)
  default     = {}
}

variable "data_cache_enabled" {
  description = "Enable the local SSD data cache (ENTERPRISE_PLUS only)."
  type        = bool
  default     = false
}

########################################
# Backups and maintenance
########################################

variable "backup_start_time" {
  description = "Start of the daily automated backup window, HH:MM in UTC."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM (24h, UTC)."
  }
}

variable "retained_backups" {
  description = "Number of daily automated backups to keep. Defaults to 30 in prod and 7 elsewhere."
  type        = number
  default     = null
}

variable "transaction_log_retention_days" {
  description = "Days of write-ahead logs kept for point-in-time recovery (1-35 for Enterprise, 1-35 for Enterprise Plus)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window_day" {
  description = "Day of week for the maintenance window (1 = Monday ... 7 = Sunday)."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "maintenance_window_day must be between 1 and 7."
  }
}

variable "maintenance_window_hour" {
  description = "Hour of day (UTC, 0-23) at which the maintenance window starts."
  type        = number
  default     = 3

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "maintenance_window_hour must be between 0 and 23."
  }
}

variable "maintenance_update_track" {
  description = "Maintenance timing: canary, stable or week5."
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["canary", "stable", "week5"], var.maintenance_update_track)
    error_message = "maintenance_update_track must be canary, stable or week5."
  }
}

variable "deny_maintenance_periods" {
  description = "Windows during which Cloud SQL must not perform maintenance (e.g. change freezes). Dates are YYYY-MM-DD, time is HH:MM:SS UTC."
  type = list(object({
    start_date = string
    end_date   = string
    time       = optional(string, "00:00:00")
  }))
  default = []
}

########################################
# Databases and access
########################################

variable "databases" {
  description = "Databases to create on the instance, keyed by name. Charset/collation default to UTF8 / en_US.UTF8."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "iam_principals" {
  description = "Google identities granted a login on the instance via Cloud SQL IAM authentication. Accepts user emails and service-account emails; the type is derived from the address. Grant privileges inside PostgreSQL to the resulting role as usual."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.iam_principals : can(regex("^[^@\\s]+@[^@\\s]+$", p))])
    error_message = "Every iam_principal must be an email address (user or service account)."
  }
}

########################################
# Lifecycle and metadata
########################################

variable "deletion_protection" {
  description = "Prevent the instance from being destroyed, both by OpenTofu and by the Cloud SQL API. Set to false only when decommissioning."
  type        = bool
  default     = true
}

variable "query_insights_enabled" {
  description = "Enable Query Insights (per-query performance telemetry)."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional labels applied to the instance. The module always adds environment and managed-by."
  type        = map(string)
  default     = {}
}
