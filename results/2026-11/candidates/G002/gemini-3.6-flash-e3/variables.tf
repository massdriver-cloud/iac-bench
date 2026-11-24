variable "name" {
  type        = string
  description = "The name of the Cloud SQL PostgreSQL instance."
}

variable "project_id" {
  type        = string
  description = "The GCP project ID in which the instance will be created."
}

variable "network_id" {
  type        = string
  description = "The self-link or resource ID of the VPC network for Private Services Access."
}

variable "database_version" {
  type        = string
  default     = "POSTGRES_15"
  description = "The PostgreSQL version to use (e.g. POSTGRES_15, POSTGRES_16, POSTGRES_14)."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "The GCP region where the instance will be deployed."
}

variable "tier" {
  type        = string
  default     = "db-custom-2-7680"
  description = "The machine type / tier for the Cloud SQL instance."
}

variable "availability_type" {
  type        = string
  default     = "REGIONAL"
  description = "The availability type for the instance: REGIONAL for High Availability or ZONAL."
}

variable "disk_type" {
  type        = string
  default     = "PD_SSD"
  description = "The type of storage disk (PD_SSD or PD_HDD)."
}

variable "disk_size" {
  type        = number
  default     = 20
  description = "The size of data disk in GB."
}

variable "disk_autoresize" {
  type        = bool
  default     = true
  description = "Configuration to increase storage size automatically."
}

variable "disk_autoresize_limit" {
  type        = number
  default     = 0
  description = "Maximum size to which storage can auto-increase (0 for unlimited)."
}

variable "enable_public_ip" {
  type        = bool
  default     = false
  description = "Whether to allocate a public IPv4 address to the instance."
}

variable "allocated_ip_range" {
  type        = string
  default     = null
  description = "The name of the allocated IP range for Private Services Access."
}

variable "ssl_mode" {
  type        = string
  default     = "ENCRYPTED_ONLY"
  description = "The SSL mode requirement for incoming connections (ENCRYPTED_ONLY, TRUSTED_CLIENT_CERTIFICATE_REQUIRED, ALLOW_UNENCRYPTED_AND_ENCRYPTED)."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Whether deletion protection is enabled for the database instance."
}

variable "root_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Password for the default 'postgres' user. If null, a random password will be generated."
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

variable "users" {
  type = list(object({
    name     = string
    password = optional(string)
  }))
  default     = []
  description = "List of standard built-in database users to create."
}

variable "iam_users" {
  type        = list(string)
  default     = []
  description = "List of Google Account email addresses to grant IAM database user access."
}

variable "iam_service_accounts" {
  type        = list(string)
  default     = []
  description = "List of Service Account emails to grant IAM database service account access."
}

variable "database_flags" {
  type = list(object({
    name  = string
    value = string
  }))
  default     = []
  description = "List of custom PostgreSQL database flags to apply."
}

variable "backup_configuration" {
  type = object({
    enabled                        = optional(bool, true)
    start_time                     = optional(string, "03:00")
    location                       = optional(string)
    point_in_time_recovery_enabled = optional(bool, true)
    transaction_log_retention_days = optional(number, 7)
    retained_backups               = optional(number, 14)
    retention_unit                 = optional(string, "COUNT")
  })
  default     = {}
  description = "Configuration for instance backups and point-in-time recovery."
}

variable "maintenance_window" {
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string, "stable")
  })
  default     = {}
  description = "Maintenance window configuration (day 1-7, hour 0-23)."
}

variable "insights_config" {
  type = object({
    query_insights_enabled  = optional(bool, true)
    query_string_length     = optional(number, 1024)
    record_application_tags = optional(bool, true)
    record_client_address   = optional(bool, true)
  })
  default     = {}
  description = "Query Insights configuration for performance monitoring."
}

variable "grant_iam_roles" {
  type        = bool
  default     = true
  description = "Whether to grant Cloud SQL Client and Instance User IAM roles on the project level to the IAM users and service accounts."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels to assign to the Cloud SQL instance."
}
