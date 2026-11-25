variable "environment" {
  description = "Environment whose existing apps VPC will host the private connection."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Choose dev, staging or prod."
  }
}

variable "instance_name" {
  description = "Cloud SQL instance ID, unique in the provider project."
  type        = string
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.instance_name))
    error_message = "Use a lowercase Cloud SQL instance ID."
  }
}

variable "region" {
  description = "Google Cloud region for the instance."
  type        = string
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL version identifier (for example POSTGRES_16)."
  type        = string
  validation {
    condition     = can(regex("^POSTGRES_[0-9]+(_[0-9]+)?$", var.database_version))
    error_message = "Only Cloud SQL PostgreSQL versions are supported."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier compatible with the chosen region, edition and version."
  type        = string
}

variable "edition" {
  description = "Cloud SQL edition; set explicitly to avoid version-dependent API defaults."
  type        = string
  default     = "ENTERPRISE"
  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "Choose ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "REGIONAL provides cross-zone failover; choose ZONAL for workloads not requiring HA."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Choose REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD capacity in GB; subsequent growth is managed by Cloud SQL."
  type        = number
  default     = 10
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Specify a whole number of GB, at least 10."
  }
}

variable "backup_start_time" {
  description = "Daily backup window start in UTC (HH:MM)."
  type        = string
  default     = "02:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Use a UTC time in HH:MM format."
  }
}

variable "maintenance_window" {
  description = "Optional maintenance start, UTC: Monday=1 through Sunday=7."
  type        = object({ day = number, hour = number })
  default     = null
  validation {
    condition     = var.maintenance_window == null ? true : contains(range(1, 8), var.maintenance_window.day) && contains(range(24), var.maintenance_window.hour)
    error_message = "Specify day 1-7 and hour 0-23."
  }
}

variable "database_flags" {
  description = "Additional supported Cloud SQL PostgreSQL flags. IAM authentication is module-owned."
  type        = map(string)
  default     = {}
  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "Do not set the module-managed IAM authentication flag."
  }
}

variable "deletion_protection" {
  description = "Protect the instance in OpenTofu and Cloud SQL; disable and apply before intentional deletion."
  type        = bool
  default     = true
}

variable "databases" {
  description = "Additional application database names to create (not the built-in postgres database)."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "Identity email => CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT. Supply full service account emails."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for email, kind in var.iam_users : can(regex("^[^@ ]+@[^@ ]+$", email)) && (kind == "CLOUD_IAM_USER" || (kind == "CLOUD_IAM_SERVICE_ACCOUNT" && endswith(email, ".gserviceaccount.com")))])
    error_message = "Supply identity emails mapped to IAM user or service account types."
  }
}
