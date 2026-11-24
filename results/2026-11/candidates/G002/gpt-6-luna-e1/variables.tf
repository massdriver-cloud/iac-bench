variable "project_id" {
  description = "Google Cloud project that owns the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the Cloud SQL instance, for example us-central1."
  type        = string
}

variable "instance_name" {
  description = "Globally unique Cloud SQL instance name within the project."
  type        = string
}

variable "network" {
  description = "VPC network self-link with Private Services Access already configured. The instance is private-IP-only."
  type        = string
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version."
  type        = string
  default     = "POSTGRES_16"
}

variable "tier" {
  description = "Cloud SQL machine tier; choose to match the workload and environment."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "Availability configuration: ZONAL or REGIONAL. Production should generally use REGIONAL."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_type" {
  description = "Persistent disk type used for database storage."
  type        = string
  default     = "PD_SSD"
  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_size_gb" {
  description = "Initial persistent disk size in GiB. Disk autoresize is enabled by default."
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10 GiB."
  }
}

variable "disk_autoresize" {
  description = "Automatically grow database storage when required."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum disk size in GiB; 0 means no configured maximum."
  type        = number
  default     = 0
}

variable "deletion_protection" {
  description = "Protect the instance from accidental deletion both in Cloud SQL and through Terraform."
  type        = bool
  default     = true
}

variable "backup_retained_backups" {
  description = "Number of automated backups to retain."
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retained_backups >= 1 && var.backup_retained_backups <= 365
    error_message = "backup_retained_backups must be between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of PostgreSQL transaction logs retained for point-in-time recovery."
  type        = number
  default     = 7
  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7
    error_message = "transaction_log_retention_days must be between 1 and 7."
  }
}

variable "backup_start_time" {
  description = "Preferred daily backup start time in UTC, in HH:MM format."
  type        = string
  default     = "03:00"
}

variable "maintenance_day" {
  description = "Preferred weekly maintenance day (1-7, Monday-Sunday)."
  type        = number
  default     = 7
  validation {
    condition     = var.maintenance_day >= 1 && var.maintenance_day <= 7
    error_message = "maintenance_day must be from 1 (Monday) to 7 (Sunday)."
  }
}

variable "maintenance_hour" {
  description = "Preferred maintenance hour in UTC (0-23)."
  type        = number
  default     = 4
  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23
    error_message = "maintenance_hour must be from 0 to 23."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL database flags. cloudsql.iam_authentication is managed by this module and must not be set here."
  type        = map(string)
  default     = {}
  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is module-managed and must not be supplied in database_flags."
  }
}

variable "databases" {
  description = "Names of application databases to create on this instance."
  type        = set(string)
  default     = []
}

variable "iam_database_users" {
  description = "IAM identities to provision as PostgreSQL login users, keyed by identity email. Values must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT. Grant database privileges separately using PostgreSQL roles/grants."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for user_type in values(var.iam_database_users) : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], user_type)
    ])
    error_message = "IAM user types must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}

variable "labels" {
  description = "Labels applied to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}
