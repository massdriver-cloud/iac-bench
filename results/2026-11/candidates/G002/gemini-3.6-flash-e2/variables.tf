variable "instance_name" {
  type        = string
  description = "Name of the Cloud SQL PostgreSQL instance."
}

variable "project_id" {
  type        = string
  description = "The GCP project ID in which to deploy the instance."
}

variable "private_network" {
  type        = string
  description = "The resource link of the VPC network to attach to private services access (e.g. projects/PROJECT_ID/global/networks/apps-dev)."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "The GCP region for the Cloud SQL instance."
}

variable "database_version" {
  type        = string
  default     = "POSTGRES_15"
  description = "The PostgreSQL database version (e.g. POSTGRES_14, POSTGRES_15, POSTGRES_16)."
}

variable "tier" {
  type        = string
  default     = "db-custom-2-7680"
  description = "The machine tier/size for the Cloud SQL instance."
}

variable "availability_type" {
  type        = string
  default     = "REGIONAL"
  description = "The availability type for HA. Standard choices are REGIONAL (high availability) or ZONAL."
}

variable "disk_type" {
  type        = string
  default     = "PD_SSD"
  description = "The storage disk type (PD_SSD or PD_HDD)."
}

variable "disk_size" {
  type        = number
  default     = 20
  description = "The initial disk size in GB."
}

variable "disk_autoresize" {
  type        = bool
  default     = true
  description = "Whether to automatically increase disk size when storage is low."
}

variable "disk_autoresize_limit" {
  type        = number
  default     = 0
  description = "Maximum size to which storage can auto-resize (0 for unlimited)."
}

variable "ipv4_enabled" {
  type        = bool
  default     = false
  description = "Whether public IPv4 address should be assigned. Defaults to false for private network security."
}

variable "ssl_mode" {
  type        = string
  default     = "ENCRYPTED_ONLY"
  description = "The SSL mode for connections (e.g. ENCRYPTED_ONLY, TRUSTED_CLIENT_CERTIFICATE_REQUIRED, ALLOW_UNENCRYPTED_AND_WITHOUT_CLIENT_CERT)."
}

variable "enable_private_path" {
  type        = bool
  default     = true
  description = "Whether to enable private path for Google Cloud services."
}

variable "backup_enabled" {
  type        = bool
  default     = true
  description = "Whether automated daily backups are enabled."
}

variable "backup_start_time" {
  type        = string
  default     = "03:00"
  description = "HH:MM format start time for daily backup window in UTC."
}

variable "point_in_time_recovery_enabled" {
  type        = bool
  default     = true
  description = "Whether point-in-time recovery is enabled (requires write-ahead logging)."
}

variable "transaction_log_retention_days" {
  type        = number
  default     = 7
  description = "Number of days transaction logs are retained for point-in-time recovery."
}

variable "retained_backups" {
  type        = number
  default     = 7
  description = "Number of daily backups to retain."
}

variable "maintenance_window_day" {
  type        = number
  default     = 7
  description = "Day of week (1-7, 7 = Sunday) for maintenance window."
}

variable "maintenance_window_hour" {
  type        = number
  default     = 4
  description = "Hour of day (0-23 UTC) for maintenance window."
}

variable "maintenance_window_update_track" {
  type        = string
  default     = "stable"
  description = "Maintenance update track (stable or canary)."
}

variable "query_insights_enabled" {
  type        = bool
  default     = true
  description = "Whether Query Insights is enabled for database performance monitoring."
}

variable "query_string_length" {
  type        = number
  default     = 1024
  description = "Maximum length of query statements recorded by Query Insights."
}

variable "record_application_tags" {
  type        = bool
  default     = true
  description = "Record application tags in Query Insights."
}

variable "record_client_address" {
  type        = bool
  default     = true
  description = "Record client address in Query Insights."
}

variable "query_plans_per_minute" {
  type        = number
  default     = 5
  description = "Number of query plans recorded per minute by Query Insights."
}

variable "database_flags" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = []
  description = "List of custom PostgreSQL database flags to apply."
}

variable "databases" {
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default     = []
  description = "List of databases to create on the instance."
}

variable "iam_users" {
  type        = list(string)
  default     = []
  description = "List of Google Cloud user emails (human identities) to grant IAM database access."
}

variable "iam_service_accounts" {
  type        = list(string)
  default     = []
  description = "List of Google Cloud service account emails (workload identities) to grant IAM database access."
}

variable "db_users" {
  type = list(object({
    name     = string
    password = string
  }))
  default     = []
  description = "List of built-in database users to create with passwords."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "User-defined labels to apply to the instance."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Whether deletion protection is enabled on the instance."
}
