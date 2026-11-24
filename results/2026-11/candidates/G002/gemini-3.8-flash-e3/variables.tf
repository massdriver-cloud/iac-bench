variable "instance_name" {
  type        = string
  description = "The name of the Cloud SQL PostgreSQL instance."
}

variable "vpc_network" {
  type        = string
  description = "The VPC network self link, resource ID, or network name where Cloud SQL connects via Private Services Access (e.g. 'apps-dev', 'apps-staging', 'apps-prod', or 'projects/PROJECT_ID/global/networks/NETWORK_NAME')."
}

variable "project" {
  type        = string
  default     = null
  description = "The Google Cloud project ID. Defaults to the provider project or the project parsed from vpc_network."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "The GCP region for the Cloud SQL instance."
}

variable "zone" {
  type        = string
  default     = null
  description = "The preferred primary GCP zone for the Cloud SQL instance (e.g. 'us-central1-a')."
}

variable "secondary_zone" {
  type        = string
  default     = null
  description = "The preferred secondary/standby GCP zone for regional high availability (e.g. 'us-central1-f')."
}

variable "database_version" {
  type        = string
  default     = "POSTGRES_15"
  description = "The PostgreSQL database version (e.g. 'POSTGRES_15', 'POSTGRES_16', 'POSTGRES_14')."
}

variable "tier" {
  type        = string
  default     = "db-custom-2-7680"
  description = "The machine type / tier for the Cloud SQL instance (e.g. 'db-custom-2-7680', 'db-custom-4-15360')."
}

variable "availability_type" {
  type        = string
  default     = "REGIONAL"
  description = "The availability type: 'REGIONAL' (multi-zone high availability with automatic failover) or 'ZONAL' (single zone)."
}

variable "disk_size" {
  type        = number
  default     = 20
  description = "Initial storage capacity in GB."
}

variable "disk_type" {
  type        = string
  default     = "PD_SSD"
  description = "Storage type: 'PD_SSD' or 'PD_HDD'."
}

variable "disk_autoresize" {
  type        = bool
  default     = true
  description = "Whether to allow Cloud SQL to automatically increase storage as space runs low."
}

variable "disk_autoresize_limit" {
  type        = number
  default     = 0
  description = "The maximum size in GB to which storage can auto-resize (0 indicates no limit)."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Whether deletion protection is enabled to safeguard against accidental instance destruction."
}

variable "database_flags" {
  type        = any
  default     = {}
  description = "Custom PostgreSQL database flags for DBA tuning (can be passed as a map or list of objects). Merged with baseline security flags."
}

variable "databases" {
  type        = any
  default     = []
  description = "Databases to create on the instance. Accepts list of database names or list of objects with name, charset, and collation."
}

variable "iam_users" {
  type        = set(string)
  default     = []
  description = "Google identities (engineer email addresses) to grant Cloud SQL IAM database authentication."
}

variable "iam_service_accounts" {
  type        = set(string)
  default     = []
  description = "Google service account emails (for workloads running on GKE / Compute Engine) to grant Cloud SQL IAM database authentication."
}

variable "additional_users" {
  type = list(object({
    name     = string
    password = optional(string)
    type     = optional(string, "BUILT_IN")
  }))
  default     = []
  description = "Additional database users to configure (e.g. built-in users with passwords)."
}

variable "backup_start_time" {
  type        = string
  default     = "02:00"
  description = "UTC start time for automated daily backups in HH:MM format."
}

variable "backup_retention_count" {
  type        = number
  default     = 30
  description = "Number of automated daily backups to retain."
}

variable "transaction_log_retention_days" {
  type        = number
  default     = 7
  description = "Number of days of transaction logs (WAL) to retain for point-in-time recovery."
}

variable "maintenance_window_day" {
  type        = number
  default     = 7
  description = "Day of week for the maintenance window (1-7, where 1 is Monday and 7 is Sunday)."
}

variable "maintenance_window_hour" {
  type        = number
  default     = 4
  description = "Hour of day for the maintenance window (0-23 UTC)."
}

variable "maintenance_window_update_track" {
  type        = string
  default     = "stable"
  description = "Maintenance update track: 'stable' or 'canary'."
}

variable "query_insights_enabled" {
  type        = bool
  default     = true
  description = "Whether to enable Cloud SQL Query Insights for database performance diagnostics."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "User-defined labels to apply to the instance."
}

variable "google_access_token" {
  type        = string
  default     = "dummy"
  description = "OAuth2 access token for the Google provider (defaults to a placeholder for offline operations)."
}
