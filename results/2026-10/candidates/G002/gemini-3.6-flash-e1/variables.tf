variable "name" {
  description = "The name of the Cloud SQL PostgreSQL instance."
  type        = string
}

variable "private_network" {
  description = "The VPC network self-link or URI (e.g., projects/PROJECT_ID/global/networks/apps-dev) for Private Services Access."
  type        = string
}

variable "project_id" {
  description = "The GCP project ID to host the instance in. If null, provider default project is used."
  type        = string
  default     = null
}

variable "region" {
  description = "The GCP region for the Cloud SQL instance."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The preferred GCP zone for the primary instance location."
  type        = string
  default     = null
}

variable "database_version" {
  description = "The PostgreSQL database version (e.g., POSTGRES_16, POSTGRES_15, POSTGRES_14)."
  type        = string
  default     = "POSTGRES_16"
}

variable "tier" {
  description = "The machine tier / type for the Cloud SQL instance (e.g., db-custom-2-7680)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "The availability type for the instance: REGIONAL for High Availability (HA) or ZONAL."
  type        = string
  default     = "REGIONAL"
}

variable "disk_type" {
  description = "The storage disk type: PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"
}

variable "disk_size" {
  description = "Initial disk size in GB."
  type        = number
  default     = 20
}

variable "disk_autoresize_limit" {
  description = "Maximum limit for disk auto-resize in GB (0 means no limit)."
  type        = number
  default     = 0
}

variable "ipv4_enabled" {
  description = "Whether public IPv4 is assigned to the instance. Default is false (Private IP only)."
  type        = bool
  default     = false
}

variable "ssl_mode" {
  description = "SSL/TLS connection mode: ENCRYPTED_ONLY, TRUSTED_CLIENT_CERTIFICATE_REQUIRED, or ALLOW_UNENCRYPTED_AND_ENCRYPTED."
  type        = string
  default     = "ENCRYPTED_ONLY"
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled for the Cloud SQL instance."
  type        = bool
  default     = true
}

variable "user_labels" {
  description = "User labels to assign to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}

variable "backup_start_time" {
  description = "UTC start time for automated backups in HH:MM format."
  type        = string
  default     = "03:00"
}

variable "backup_retention_days" {
  description = "Number of automated backups to retain."
  type        = number
  default     = 14
}

variable "backup_transaction_log_retention_days" {
  description = "Number of days of transaction logs to retain for point-in-time recovery."
  type        = number
  default     = 7
}

variable "maintenance_window_day" {
  description = "Day of week for maintenance window (1-7, where 7 is Sunday)."
  type        = number
  default     = 7
}

variable "maintenance_window_hour" {
  description = "Hour of day (0-23 UTC) for maintenance window."
  type        = number
  default     = 3
}

variable "maintenance_window_update_track" {
  description = "Maintenance update track: stable or canary."
  type        = string
  default     = "stable"
}

variable "query_insights_enabled" {
  description = "Whether Query Insights is enabled for performance troubleshooting."
  type        = bool
  default     = true
}

variable "query_insights_record_application_tags" {
  description = "Record application tags in Query Insights."
  type        = bool
  default     = true
}

variable "query_insights_record_client_address" {
  description = "Record client address in Query Insights."
  type        = bool
  default     = true
}

variable "query_insights_query_plans_per_minute" {
  description = "Number of query plans recorded per minute by Query Insights."
  type        = number
  default     = 5
}

variable "query_insights_query_string_length" {
  description = "Query string length in bytes captured by Query Insights."
  type        = number
  default     = 1024
}

variable "master_instance_name" {
  description = "Name of the master Cloud SQL instance if creating a read replica."
  type        = string
  default     = null
}

variable "encryption_key_name" {
  description = "Customer Managed Encryption Key (CMEK) KMS key name."
  type        = string
  default     = null
}

variable "databases" {
  description = "List of databases to create on the Cloud SQL instance."
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = []
}

variable "users" {
  description = "List of built-in SQL database users to create."
  type = list(object({
    name     = string
    password = string
  }))
  default = []
}

variable "iam_users" {
  description = "List of Google IAM identities (users or service accounts) to grant Cloud SQL database access to."
  type = list(object({
    email = string
    type  = optional(string)
  }))
  default = []
}

variable "grant_iam_roles" {
  description = "Whether to grant roles/cloudsql.client and roles/cloudsql.instanceUser IAM roles to specified IAM identities."
  type        = bool
  default     = true
}

variable "database_flags" {
  description = "Custom PostgreSQL database flags. cloudsql.iam_authentication is automatically enforced."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}
