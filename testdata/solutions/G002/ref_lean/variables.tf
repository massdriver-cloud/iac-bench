variable "name" {
  description = "Instance name, unique within the project (e.g. orders-db)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,61}[a-z0-9]$", var.name))
    error_message = "name must be 4-63 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "network" {
  description = "Name of the environment's VPC network (e.g. apps-prod). The instance attaches over private IP; the network must already have private services access configured."
  type        = string
}

variable "environment" {
  description = "Deployment environment. prod runs a regional (high-availability) instance with longer backup retention; dev and staging run zonal."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "tier" {
  description = "Machine tier (e.g. db-custom-2-7680)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = number
  default     = 17

  validation {
    condition     = contains([15, 16, 17], var.postgres_version)
    error_message = "postgres_version must be 15, 16, or 17."
  }
}

variable "database_flags" {
  description = "PostgreSQL flags to set on the instance, as name => value."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "Databases to create on the instance. While deletion protection is on, removing one leaves its data in place."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "IAM principals (user emails) granted database login through IAM authentication."
  type        = set(string)
  default     = []
}

variable "maintenance_window" {
  description = "Weekly maintenance window: day (1 = Monday .. 7 = Sunday) and hour (0-23, UTC)."
  type = object({
    day  = number
    hour = number
  })
  default = { day = 7, hour = 3 }

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.day must be 1-7 and hour 0-23."
  }
}

variable "backup_start_time" {
  description = "Daily backup start time, HH:MM in UTC."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM (24-hour, UTC)."
  }
}

variable "disk_size_gb" {
  description = "Initial disk size in GB; the disk grows automatically from here."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "backups_enabled" {
  description = "Automated daily backups with point-in-time recovery. Disable only for disposable instances."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Protect the instance from deletion. Set false only to retire it."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Extra labels to apply to the instance."
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "GCP region the instance runs in."
  type        = string
  default     = "us-central1"
}
