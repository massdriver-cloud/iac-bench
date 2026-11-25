variable "project_id" {
  description = "The ID of the GCP project where the Cloud SQL instance will be created."
  type        = string
}

variable "region" {
  description = "The GCP region to deploy the instance in."
  type        = string
}

variable "instance_name" {
  description = "The name of the Cloud SQL instance."
  type        = string
}

variable "network" {
  description = "The VPC network self_link where the database will be accessible via private services access."
  type        = string
}

variable "database_version" {
  description = "The PostgreSQL version to use."
  type        = string
  default     = "POSTGRES_15"
}

variable "tier" {
  description = "The machine type to use for the Cloud SQL instance."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "The availability type of the Cloud SQL instance, high availability (REGIONAL) or single zone (ZONAL)."
  type        = string
  default     = "REGIONAL"
}

variable "disk_size" {
  description = "The size of data disk, in GB."
  type        = number
  default     = 100
}

variable "disk_type" {
  description = "The type of data disk: PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"
}

variable "disk_autoresize" {
  description = "Configuration to increase storage size automatically."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Whether or not to allow Terraform to destroy the instance."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "HH:MM format time indicating when backup configuration starts."
  type        = string
  default     = "02:00"
}

variable "maintenance_window_day" {
  description = "Day of week (1-7), starting on Monday, on which maintenance should be performed."
  type        = number
  default     = 7 # Sunday
}

variable "maintenance_window_hour" {
  description = "Hour of day (0-23) on which maintenance should be performed."
  type        = number
  default     = 3
}

variable "maintenance_track" {
  description = "Receive updates earlier (canary) or later (stable)."
  type        = string
  default     = "stable"
}

variable "database_flags" {
  description = "Additional database flags to set on the instance. IAM authentication is always enabled."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}
