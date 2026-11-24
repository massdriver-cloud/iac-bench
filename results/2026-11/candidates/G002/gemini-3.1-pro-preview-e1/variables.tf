variable "project_id" {
  type        = string
  description = "The ID of the project in which to provision resources."
  default     = null
}

variable "name" {
  type        = string
  description = "Name of the PostgreSQL instance."
}

variable "region" {
  type        = string
  description = "The region to deploy the instance in."
}

variable "database_version" {
  type        = string
  description = "The PostgreSQL version to use."
  default     = "POSTGRES_15"
}

variable "tier" {
  type        = string
  description = "The machine tier (e.g., db-custom-2-7680 or db-f1-micro)."
}

variable "network_id" {
  type        = string
  description = "The VPC Network ID where Private Services Access is configured (e.g. projects/my-project/global/networks/apps-prod)."
}

variable "availability_type" {
  type        = string
  description = "The availability type of the Cloud SQL instance, high availability (REGIONAL) or single zone (ZONAL)."
  default     = "REGIONAL"
}

variable "disk_size" {
  type        = number
  description = "The size of data disk, in GB."
  default     = 100
}

variable "disk_type" {
  type        = string
  description = "The type of data disk: PD_SSD or PD_HDD."
  default     = "PD_SSD"
}

variable "disk_autoresize" {
  type        = bool
  description = "Configuration to increase storage size automatically."
  default     = true
}

variable "disk_autoresize_limit" {
  type        = number
  description = "The maximum size to which storage capacity can be automatically increased. 0 means no limit."
  default     = 0
}

variable "backup_enabled" {
  type        = bool
  description = "Whether backups are enabled."
  default     = true
}

variable "backup_start_time" {
  type        = string
  description = "HH:MM format time indicating when backup configuration starts."
  default     = "02:00"
}

variable "point_in_time_recovery_enabled" {
  type        = bool
  description = "Whether point-in-time recovery is enabled."
  default     = true
}

variable "maintenance_day" {
  type        = number
  description = "Day of week (1-7), starting on Monday, on which maintenance should be performed."
  default     = 7
}

variable "maintenance_hour" {
  type        = number
  description = "Hour of day (0-23) on which maintenance should be performed."
  default     = 2
}

variable "database_flags" {
  type        = map(string)
  description = "Additional database flags to set on the instance. IAM authentication is always enabled."
  default     = {}
}

variable "labels" {
  type        = map(string)
  description = "A map of labels to apply to the instance."
  default     = {}
}

variable "deletion_protection" {
  type        = bool
  description = "Whether deletion protection is enabled. Set to false for dev/test environments."
  default     = true
}

variable "iam_users" {
  type        = list(string)
  description = "A list of IAM users (e.g. user@example.com) to grant access to the database."
  default     = []
}

variable "iam_service_accounts" {
  type        = list(string)
  description = "A list of IAM service accounts (without .gserviceaccount.com suffix) to grant access to the database."
  default     = []
}
