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

variable "ssl_mode" {
  description = "Connection encryption: ENCRYPTED_ONLY, or TRUSTED_CLIENT_CERTIFICATE_REQUIRED to also require client certificates."
  type        = string
  default     = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"

  validation {
    condition     = contains(["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
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

  validation {
    condition     = contains([1, 2, 3, 4, 5, 6, 7], var.maintenance_day)
    error_message = "maintenance_day must be 1 (Monday) through 7 (Sunday)."
  }
}

variable "maintenance_hour" {
  description = "Maintenance hour, 0-23 UTC."
  type        = number
  default     = 4

  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23 && floor(var.maintenance_hour) == var.maintenance_hour
    error_message = "maintenance_hour must be a whole hour from 0 to 23 (UTC)."
  }
}

variable "backup" {
  description = "Backup policy. enabled = false turns off automated backups and point-in-time recovery."
  type = object({
    enabled            = optional(bool, true)
    start_time         = optional(string, "03:00")
    retained_backups   = optional(number, 14)
    log_retention_days = optional(number, 7)
  })
  default = {}

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup.start_time))
    error_message = "backup.start_time must be HH:MM (24-hour, UTC)."
  }

  validation {
    condition     = var.backup.log_retention_days >= 1 && var.backup.log_retention_days <= 7
    error_message = "backup.log_retention_days must be 1-7 on the Enterprise edition."
  }
}

variable "deletion_protection" {
  description = "Guard the instance against destroy. Set false only to retire it."
  type        = bool
  default     = true
}

variable "databases" {
  description = "Databases to create on the instance. While deletion protection is on, removing one leaves its data in place."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "Email addresses of people granted database login through IAM authentication."
  type        = set(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "Workload service-account emails granted database login through IAM authentication."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : endswith(sa, ".gserviceaccount.com")])
    error_message = "iam_service_accounts takes service-account emails ending in .gserviceaccount.com; put people in iam_users."
  }
}

variable "labels" {
  description = "Labels to apply to the instance."
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "GCP region the instance runs in."
  type        = string
  default     = "us-central1"
}

variable "kms_key_name" {
  description = "Cloud KMS key (projects/.../cryptoKeys/...) for customer-managed encryption. Only settable when the instance is created; null uses Google-managed keys."
  type        = string
  default     = null
}
