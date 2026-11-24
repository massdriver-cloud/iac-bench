variable "instance_name" {
  description = "Cloud SQL instance ID (unique within the project)."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.instance_name))
    error_message = "Use a lowercase Cloud SQL instance ID beginning with a letter and not ending in a hyphen."
  }
}

variable "environment" {
  description = "Application environment. Determines the existing apps-<environment> VPC."
  type        = string
  nullable    = false
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Choose dev, staging, or prod."
  }
}

variable "region" {
  description = "Region in which to run the instance."
  type        = string
  nullable    = false
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version, e.g. POSTGRES_16."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^POSTGRES_[0-9]+(_[0-9]+)?$", var.database_version))
    error_message = "Specify a Cloud SQL PostgreSQL version, not another database engine."
  }
}

variable "tier" {
  description = "Machine tier supported in the chosen edition, region and version."
  type        = string
  nullable    = false
}

variable "edition" {
  type        = string
  description = "Cloud SQL edition; specify explicitly even on versions whose service default is Enterprise Plus."
  default     = "ENTERPRISE"
  nullable    = false
  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "Choose ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  type        = string
  description = "REGIONAL for HA, or ZONAL for workloads which accept a single zone."
  default     = "REGIONAL"
  nullable    = false
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Choose REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  type        = number
  description = "Initial SSD size in GB. Cloud SQL will grow storage automatically thereafter."
  default     = 20
  nullable    = false
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Specify an integer number of GB of at least 10."
  }
}

variable "database_flags" {
  type        = map(string)
  description = "Additional PostgreSQL tuning flags supported by the selected version. IAM authentication is module-managed."
  default     = {}
  nullable    = false
  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "The module owns the IAM authentication flag."
  }
}

variable "backup_start_time" {
  description = "Start of the daily backup window in UTC (HH:MM)."
  type        = string
  default     = "03:00"
  nullable    = false
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Use a UTC time in HH:MM format."
  }
}

variable "databases" {
  type        = set(string)
  description = "Additional application database names to create (exclude system databases)."
  default     = []
  nullable    = false
}

variable "iam_users" {
  description = "Google user email addresses to provision as PostgreSQL IAM logins."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "iam_service_accounts" {
  description = "Full service account email addresses to provision as PostgreSQL IAM logins."
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for email in var.iam_service_accounts : endswith(email, ".gserviceaccount.com")])
    error_message = "Provide full service account email addresses including .gserviceaccount.com."
  }
}

variable "deletion_protection" {
  description = "Protect against deletion via OpenTofu and the Cloud SQL API. Disable and apply only for intentional decommissioning."
  type        = bool
  default     = true
  nullable    = false
}
