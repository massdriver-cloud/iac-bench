variable "name" {
  description = "Cloud SQL instance ID."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.name))
    error_message = "Use a lowercase Cloud SQL instance ID."
  }
}

variable "environment" {
  description = "Selects the network apps-<environment> in the provider project."
  type        = string
  nullable    = false
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Select dev, staging, or prod."
  }
}

variable "region" {
  type        = string
  description = "Google Cloud region for the instance."
  nullable    = false
}

variable "database_version" {
  description = "Supported Cloud SQL PostgreSQL major version, e.g. POSTGRES_16."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "Use a PostgreSQL engine version such as POSTGRES_16."
  }
}

variable "tier" {
  description = "Machine tier compatible with the selected edition, region, and availability."
  type        = string
  nullable    = false
}

variable "edition" {
  type     = string
  default  = "ENTERPRISE"
  nullable = false
  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "Choose ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "REGIONAL for HA; ZONAL for a single zone."
  type        = string
  default     = "REGIONAL"
  nullable    = false
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Select REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD capacity in GB. Automatic increases are enabled."
  type        = number
  default     = 20
  nullable    = false
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Specify at least 10 whole GB."
  }
}

variable "database_flags" {
  description = "Additional engine flags; IAM authentication is managed by the module."
  type        = map(string)
  default     = {}
  nullable    = false
  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "The IAM authentication flag is reserved."
  }
}

variable "iam_users" {
  description = "Human Google identity email addresses to register as database logins."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "iam_service_accounts" {
  description = "Service account emails to register as database logins."
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for email in var.iam_service_accounts : endswith(email, ".gserviceaccount.com")])
    error_message = "Use full service account emails."
  }
}

variable "databases" {
  description = "Additional PostgreSQL databases to create."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "deletion_protection" {
  description = "Guard deletion in both OpenTofu and the Cloud SQL API."
  type        = bool
  default     = true
  nullable    = false
}

variable "backup_start_time" {
  description = "Daily backup window start in UTC (HH:MM)."
  type        = string
  default     = "03:00"
  nullable    = false
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Use HH:MM (UTC)."
  }
}

variable "maintenance_window" {
  description = "Optional weekly maintenance window (day 1=Monday through 7=Sunday; hour UTC)."
  type        = object({ day = number, hour = number })
  default     = null
  validation {
    condition     = var.maintenance_window == null ? true : (contains(range(1, 8), var.maintenance_window.day) && contains(range(24), var.maintenance_window.hour))
    error_message = "Provide day 1-7 and hour 0-23."
  }
}
