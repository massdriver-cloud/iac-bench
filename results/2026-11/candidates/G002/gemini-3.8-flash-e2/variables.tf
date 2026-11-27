variable "name" {
  type        = string
  description = "The name of the Cloud SQL PostgreSQL instance."
}

variable "network" {
  type        = string
  description = "The VPC network to connect the instance to (e.g. 'apps-dev', 'apps-staging', 'apps-prod', or a full network self-link). Applications connect via Private Services Access."
}

variable "project_id" {
  type        = string
  default     = null
  description = "The Google Cloud project ID. If null, the provider's configured project is used."
}

variable "region" {
  type        = string
  default     = null
  description = "The Google Cloud region for the instance. If null, defaults to the provider's region or 'us-central1'."
}

variable "zone" {
  type        = string
  default     = null
  description = "The primary zone for the instance (e.g. 'us-central1-a'). If null, Google Cloud assigns a zone automatically."
}

variable "secondary_zone" {
  type        = string
  default     = null
  description = "The secondary zone for regional high availability standby (e.g. 'us-central1-b')."
}

variable "database_version" {
  type        = string
  default     = "POSTGRES_15"
  description = "The PostgreSQL database version to run (e.g. 'POSTGRES_15', 'POSTGRES_16', 'POSTGRES_14')."
}

variable "tier" {
  type        = string
  default     = "db-custom-2-7680"
  description = "The machine tier (compute & RAM) for the instance (e.g. 'db-custom-2-7680', 'db-custom-4-16384')."
}

variable "availability_type" {
  type        = string
  default     = "REGIONAL"
  description = "The availability type of the instance: 'REGIONAL' (for multi-zone HA failover) or 'ZONAL' (single zone)."
}

variable "edition" {
  type        = string
  default     = "ENTERPRISE"
  description = "The edition of the instance: 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
}

variable "disk_size" {
  type        = number
  default     = 50
  description = "Initial storage size in gigabytes (GB)."
}

variable "disk_type" {
  type        = string
  default     = "PD_SSD"
  description = "The disk type for the storage volume: 'PD_SSD' or 'PD_HDD'."
}

variable "disk_autoresize" {
  type        = bool
  default     = true
  description = "Whether to enable automatic storage capacity increases as data grows."
}

variable "disk_autoresize_limit" {
  type        = number
  default     = 0
  description = "The maximum size in GB to which the disk can automatically grow. 0 indicates no limit."
}

variable "allocated_ip_range" {
  type        = string
  default     = null
  description = "The name of the allocated IP range for Private Services Access peering, if a specific range is used."
}

variable "ssl_mode" {
  type        = string
  default     = "ENCRYPTED_ONLY"
  description = "SSL mode for client connections ('ENCRYPTED_ONLY', 'TRUSTED_CLIENT_CERTIFICATES', 'ALLOW_UNENCRYPTED_AND_ENCRYPTED')."
}

variable "enable_private_path_for_google_cloud_services" {
  type        = bool
  default     = true
  description = "Whether to enable private path for Google Cloud services over Private Services Access."
}

variable "databases" {
  type        = any
  default     = []
  description = "List of databases to create on the instance. Can be database names (strings) or objects with { name, charset, collation }."
}

variable "iam_users" {
  type        = list(string)
  default     = []
  description = "List of Google user account email addresses (engineers) to grant Cloud SQL IAM database access to."
}

variable "iam_service_accounts" {
  type        = list(string)
  default     = []
  description = "List of Google Service Account emails (GKE/Compute Engine workloads) to grant Cloud SQL IAM database access to."
}

variable "iam_groups" {
  type        = list(string)
  default     = []
  description = "List of Google Group email addresses to grant Cloud SQL IAM database access to."
}

variable "additional_users" {
  type = list(object({
    name     = string
    password = optional(string)
  }))
  default     = []
  description = "Optional list of built-in SQL users."
}

variable "database_flags" {
  type        = map(string)
  default     = {}
  description = "DBA-managed custom PostgreSQL configuration flags. Merged with standard baseline flags (custom values override defaults)."
}

variable "backup_start_time" {
  type        = string
  default     = "02:00"
  description = "Start time for daily automated backup window in HH:MM format (UTC)."
}

variable "retained_backups" {
  type        = number
  default     = 7
  description = "Number of daily automated backups to retain."
}

variable "transaction_log_retention_days" {
  type        = number
  default     = 7
  description = "The number of days of transaction logs (WAL) to retain for Point-in-Time Recovery (1-7 days)."
}

variable "maintenance_window_day" {
  type        = number
  default     = 7
  description = "Day of week for scheduled maintenance window (1-7, where 7 is Sunday)."
}

variable "maintenance_window_hour" {
  type        = number
  default     = 3
  description = "Hour of day (0-23 UTC) for scheduled maintenance window."
}

variable "maintenance_window_update_track" {
  type        = string
  default     = "stable"
  description = "Maintenance release channel: 'canary' or 'stable'."
}

variable "insights_config" {
  type = object({
    query_insights_enabled  = optional(bool, true)
    query_string_length     = optional(number, 1024)
    record_application_tags = optional(bool, true)
    record_client_address   = optional(bool, true)
    query_plans_per_minute  = optional(number, 5)
  })
  default = {
    query_insights_enabled  = true
    query_string_length     = 1024
    record_application_tags = true
    record_client_address   = true
    query_plans_per_minute  = 5
  }
  description = "Configuration for Query Insights query performance diagnostics."
}

variable "read_replicas" {
  type = map(object({
    tier            = optional(string)
    zone            = optional(string)
    region          = optional(string)
    disk_size       = optional(number)
    disk_type       = optional(string, "PD_SSD")
    disk_autoresize = optional(bool, true)
    database_flags  = optional(map(string), {})
  }))
  default     = {}
  description = "Map of read replicas to manage for this database instance."
}

variable "deletion_protection" {
  type        = bool
  default     = false
  description = "Whether deletion protection is enabled on the instance. Set to true in production."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "A map of key-value user labels to assign to the instance."
}
