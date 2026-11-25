variable "instance_name" {
  description = "Cloud SQL instance ID, unique in the provider project. Changing it replaces the instance."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.instance_name))
    error_message = "Use 1–98 lowercase letters, digits, or hyphens; start with a letter and end with a letter or digit."
  }
}

variable "environment" {
  description = "Chooses the existing apps-<environment> VPC in the provider project."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "region" {
  description = "Google Cloud region for the instance."
  type        = string
  nullable    = false
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL version, e.g. POSTGRES_16. Choose a version available for the region and edition."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "Use a Cloud SQL PostgreSQL version such as POSTGRES_16."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier compatible with the selected edition and region."
  type        = string
  nullable    = false
}

variable "edition" {
  description = "Cloud SQL edition."
  type        = string
  default     = "ENTERPRISE"
  nullable    = false

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "Edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "Override the HA default: REGIONAL in prod, ZONAL elsewhere."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null ? true : contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "Availability type must be ZONAL or REGIONAL, or null for the environment default."
  }
}

variable "initial_disk_size_gb" {
  description = "Initial disk size in GB. Cloud SQL autoresizes the disk; this value only applies at creation."
  type        = number
  default     = 20
  nullable    = false

  validation {
    condition     = var.initial_disk_size_gb >= 10 && floor(var.initial_disk_size_gb) == var.initial_disk_size_gb
    error_message = "Initial disk size must be a whole number of GB, at least 10."
  }
}

variable "backup_start_time" {
  description = "Daily automated backup window start in UTC (HH:MM)."
  type        = string
  default     = "03:00"
  nullable    = false

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Backup start time must be a UTC time in HH:MM format."
  }
}

variable "maintenance_window" {
  description = "Optional preferred weekly maintenance window in UTC (day: 1=Monday, 7=Sunday; hour: 0–23)."
  type = object({
    day  = number
    hour = number
  })
  default = null

  validation {
    condition = var.maintenance_window == null ? true : try(
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour,
      false
    )
    error_message = "Maintenance day and hour must be whole numbers in the ranges 1–7 and 0–23."
  }
}

variable "database_flags" {
  description = "Additional Cloud SQL PostgreSQL flags. The IAM authentication and connection logging flags are managed by the module."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for name, value in var.database_flags : value != null && !contains([
        "cloudsql.iam_authentication", "log_connections", "log_disconnections"
      ], lower(name))
    ])
    error_message = "Flag values must not be null. IAM authentication and connection logging flags cannot be overridden."
  }
}

variable "databases" {
  description = "Application databases by name. Optionally set charset and collation when creating each database."
  type = map(object({
    charset   = optional(string)
    collation = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for name, config in var.databases : config != null && length(trimspace(name)) > 0 && length(name) <= 63 && !contains([
        "postgres", "template0", "template1", "cloudsqladmin"
      ], lower(name))
    ])
    error_message = "Supply a configuration for each non-system database name (1–63 characters)."
  }
}

variable "iam_users" {
  description = "Google user email addresses to provision as Cloud SQL IAM database users."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for email in var.iam_users : try(email == lower(email) && length(email) <= 63 && can(regex("^[^@\\s]+@[^@\\s]+$", email)) && !endswith(email, ".gserviceaccount.com"), false)
    ])
    error_message = "Supply lowercase Google user emails (at most 63 characters); use iam_service_accounts for service accounts."
  }
}

variable "iam_service_accounts" {
  description = "Full Google service account email addresses to provision as Cloud SQL IAM database users."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for email in var.iam_service_accounts : try(email == lower(email) && can(regex("^[^@\\s]+@[^@\\s]+\\.gserviceaccount\\.com$", email)) && length(trimsuffix(email, ".gserviceaccount.com")) <= 63, false)
    ])
    error_message = "Use lowercase full service account emails. The PostgreSQL login, without .gserviceaccount.com, must be at most 63 characters."
  }
}

variable "labels" {
  description = "Additional Cloud SQL labels. The module owns the environment and managed-by keys."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "deletion_protection" {
  description = "Protect the instance in both OpenTofu and Cloud SQL. Disable and apply separately only when intentionally decommissioning."
  type        = bool
  default     = true
  nullable    = false
}
