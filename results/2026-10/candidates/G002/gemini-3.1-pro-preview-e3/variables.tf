variable "project_id" {
  type        = string
  description = "The ID of the project in which the resource belongs."
}

variable "region" {
  type        = string
  description = "The region of the Cloud SQL instance."
}

variable "name" {
  type        = string
  description = "The name of the Cloud SQL instance."
}

variable "database_version" {
  type        = string
  description = "The database version to use."
  default     = "POSTGRES_15"
}

variable "tier" {
  type        = string
  description = "The machine type to use."
  default     = "db-custom-2-7680"
}

variable "network_self_link" {
  type        = string
  description = "The self_link of the VPC network where private services access is configured."
}

variable "high_availability" {
  type        = bool
  description = "Whether to enable high availability (REGIONAL vs ZONAL)."
  default     = false
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to enable deletion protection."
  default     = true
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

variable "database_flags" {
  type        = map(string)
  description = "Map of custom database flags to set on the instance."
  default     = {}
}

variable "labels" {
  type        = map(string)
  description = "Map of labels to apply to the instance."
  default     = {}
}

variable "databases" {
  type        = set(string)
  description = "Set of database names to create."
  default     = []
}

variable "iam_user_emails" {
  type        = set(string)
  description = "Set of IAM user email addresses to grant access."
  default     = []
}

variable "iam_service_account_emails" {
  type        = set(string)
  description = "Set of IAM service account email addresses to grant access."
  default     = []
}

variable "enable_backups" {
  type        = bool
  description = "Whether to enable automated backups."
  default     = true
}

variable "backup_start_time" {
  type        = string
  description = "HH:MM format time indicating when backup configuration starts."
  default     = "02:00"
}

variable "point_in_time_recovery_enabled" {
  type        = bool
  description = "Whether to enable point in time recovery."
  default     = true
}
