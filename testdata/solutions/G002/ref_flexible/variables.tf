variable "instance_name" {
  description = "Instance name, unique within the project."
  type        = string
}

variable "network" {
  description = "Name of the VPC network in this project for private IP. Private services access must already be configured on it."
  type        = string
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL version identifier."
  type        = string
  default     = "POSTGRES_17"

  validation {
    condition     = contains(["POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "database_version must be POSTGRES_15, POSTGRES_16, or POSTGRES_17."
  }
}

variable "tier" {
  description = "Machine tier."
  type        = string
  default     = "db-custom-4-15360"
}

variable "high_availability" {
  description = "Run a regional instance with a standby in another zone and automatic failover."
  type        = bool
  default     = false
}

variable "disk_size_gb" {
  description = "Initial disk size in GB."
  type        = number
  default     = 50
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic disk growth in GB. 0 means no limit."
  type        = number
  default     = 0
}

variable "database_flags" {
  description = "PostgreSQL flags as name => value."
  type        = map(string)
  default     = {}
}

variable "maintenance_day" {
  description = "Maintenance day, 1 = Monday .. 7 = Sunday."
  type        = number
  default     = 6
}

variable "maintenance_hour" {
  description = "Maintenance hour, 0-23 UTC."
  type        = number
  default     = 4
}

variable "backup" {
  description = "Backup policy. enabled = false turns off automated backups and point-in-time recovery."
  type = object({
    enabled              = optional(bool, true)
    start_time           = optional(string, "03:00")
    retained_backups     = optional(number, 14)
    log_retention_days   = optional(number, 7)
  })
  default = {}
}

variable "deletion_protection" {
  description = "Guard the instance against destroy. Set false only to retire it."
  type        = bool
  default     = true
}

variable "iam_users" {
  description = "IAM principals (user emails) granted database login through IAM authentication."
  type        = set(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to the instance."
  type        = map(string)
  default     = {}
}
