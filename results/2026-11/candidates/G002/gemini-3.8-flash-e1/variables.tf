variable "name" {
  type        = string
  description = "The name of the Cloud SQL PostgreSQL instance."
}

variable "environment" {
  type        = string
  description = "Target environment (dev, staging, or prod). Determines the VPC network (apps-<env>), default availability type, and deletion protection."
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "apps-dev", "apps-staging", "apps-prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod (or apps-dev, apps-staging, apps-prod)."
  }
}

variable "project" {
  type        = string
  description = "Google Cloud project ID where the instance will reside. If null, the provider's default project is used."
  default     = null
}

variable "region" {
  type        = string
  description = "Google Cloud region for the database instance."
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "Primary Compute Engine zone (e.g. us-central1-a). If null, Cloud SQL selects automatically."
  default     = null
}

variable "secondary_zone" {
  type        = string
  description = "Secondary Compute Engine zone for High Availability failover replica. If null, Cloud SQL selects automatically."
  default     = null
}

variable "network" {
  type        = string
  description = "The VPC network name or self-link for Private Services Access. If null, defaults to 'apps-<environment>'."
  default     = null
}

variable "allocated_ip_range" {
  type        = string
  description = "The name of the allocated IP range for the private IP connection. If null, Cloud SQL uses the PSA range automatically."
  default     = null
}

variable "database_version" {
  type        = string
  description = "PostgreSQL version for the database instance."
  default     = "POSTGRES_16"
}

variable "tier" {
  type        = string
  description = "Machine tier for the database instance (e.g. db-custom-2-7680, db-custom-4-16384)."
  default     = "db-custom-2-7680"
}

variable "edition" {
  type        = string
  description = "Cloud SQL edition (ENTERPRISE or ENTERPRISE_PLUS)."
  default     = "ENTERPRISE"
}

variable "availability_type" {
  type        = string
  description = "Availability type: REGIONAL (High Availability failover) or ZONAL. If null, defaults to REGIONAL for prod and ZONAL for dev/staging."
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "Availability type must be either REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  type        = number
  description = "Data disk size in gigabytes."
  default     = 20
}

variable "disk_type" {
  type        = string
  description = "Data disk storage type (PD_SSD or PD_HDD)."
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "Disk type must be either PD_SSD or PD_HDD."
  }
}

variable "disk_autoresize" {
  type        = bool
  description = "Whether to automatically increase disk storage capacity when approaching threshold."
  default     = true
}

variable "disk_autoresize_limit" {
  type        = number
  description = "Maximum size in GB to which the disk can automatically resize. 0 means unlimited."
  default     = 0
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to prevent accidental instance deletion. If null, defaults to true for prod/staging and false for dev."
  default     = null
}

variable "databases" {
  type        = any
  description = "List of databases to create on the instance. Entries can be database name strings or objects with name, charset, and collation."
  default     = []
}

variable "iam_users" {
  type        = list(string)
  description = "List of engineer Google identity email addresses to create as Cloud IAM database users."
  default     = []
}

variable "iam_service_accounts" {
  type        = list(string)
  description = "List of workload Google service account email addresses to create as Cloud IAM database service accounts."
  default     = []
}

variable "database_flags" {
  type        = map(string)
  description = "Map of custom PostgreSQL database flags. Merged with the standard baseline flags (IAM auth, pgAudit, connection logging)."
  default     = {}
}

variable "backup_configuration" {
  type = object({
    enabled                        = optional(bool, true)
    start_time                     = optional(string, "03:00")
    point_in_time_recovery_enabled = optional(bool, true)
    retained_backups               = optional(number, 14)
    transaction_log_retention_days = optional(number, 7)
  })
  description = "Backup policy and point-in-time recovery configuration."
  default     = {}
}

variable "maintenance_window" {
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 4)
    update_track = optional(string, "stable")
  })
  description = "Weekly maintenance window configuration. Day 1 is Monday, Day 7 is Sunday. Hour is 0-23 UTC."
  default     = {}
}

variable "insights_config" {
  type = object({
    query_insights_enabled  = optional(bool, true)
    query_string_length     = optional(number, 1024)
    record_application_tags = optional(bool, true)
    record_client_address   = optional(bool, true)
    query_plans_per_minute  = optional(number, 5)
  })
  description = "Query Insights configuration for performance monitoring and diagnostics."
  default     = {}
}

variable "read_replicas" {
  type = map(object({
    tier                  = optional(string)
    zone                  = optional(string)
    disk_size_gb          = optional(number)
    disk_type             = optional(string)
    disk_autoresize       = optional(bool, true)
    disk_autoresize_limit = optional(number, 0)
    database_flags        = optional(map(string), {})
  }))
  description = "Optional map of read replica instances to create, keyed by replica name."
  default     = {}
}

variable "labels" {
  type        = map(string)
  description = "Custom labels to apply to the Cloud SQL instance."
  default     = {}
}
