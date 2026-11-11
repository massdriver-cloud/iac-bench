variable "project_id" {
  description = "ID of the Google Cloud project in which the Cloud SQL instance is created."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must not be empty."
  }
}

variable "instance_name" {
  description = "Cloud SQL instance name. It must be unique within the project."
  type        = string

  validation {
    condition = (
      length(var.instance_name) >= 1 &&
      length(var.instance_name) <= 98 &&
      can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.instance_name))
    )
    error_message = "instance_name must contain only lowercase letters, numbers, and hyphens, start with a letter, end with a letter or number, and be at most 98 characters."
  }
}

variable "region" {
  description = "Google Cloud region for the instance, for example us-central1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a Google Cloud region name such as us-central1."
  }
}

variable "network_self_link" {
  description = "Self link of an existing custom VPC network with private services access already configured (for example projects/my-project/global/networks/apps-prod)."
  type        = string

  validation {
    condition = (
      can(regex("^projects/[^/]+/global/networks/[a-z][a-z0-9-]*$", var.network_self_link)) ||
      can(regex("^https://www\\.googleapis\\.com/compute/v1/projects/[^/]+/global/networks/[a-z][a-z0-9-]*$", var.network_self_link))
    )
    error_message = "network_self_link must be a full or relative VPC network self link, such as projects/my-project/global/networks/apps-prod."
  }
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_(1[3-9]|[2-9][0-9])$", var.database_version))
    error_message = "database_version must be POSTGRES_13 or a later PostgreSQL major version supported by Cloud SQL."
  }
}

variable "edition" {
  description = "Cloud SQL edition. ENTERPRISE_PLUS requires a compatible machine series and region."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "machine_type" {
  description = "Cloud SQL machine type, for example db-custom-2-7680. DBAs choose the capacity for each instance."
  type        = string
  default     = "db-custom-2-7680"

  validation {
    condition     = length(trimspace(var.machine_type)) > 0
    error_message = "machine_type must not be empty."
  }
}

variable "availability_type" {
  description = "REGIONAL configures high availability; ZONAL is suitable for disposable development instances."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "zone" {
  description = "Optional preferred zone. If omitted, Cloud SQL selects a zone in region."
  type        = string
  default     = null
  nullable    = true
}

variable "secondary_zone" {
  description = "Optional secondary zone for a REGIONAL instance. zone must also be set when this is set."
  type        = string
  default     = null
  nullable    = true
}

variable "disk_type" {
  description = "Persistent disk type. PD_SSD is the recommended default."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_size" {
  description = "Initial data disk size in GiB. Storage autoresize is always enabled."
  type        = number
  default     = 20

  validation {
    condition     = floor(var.disk_size) == var.disk_size && var.disk_size >= 10 && var.disk_size <= 65536
    error_message = "disk_size must be a whole number between 10 and 65536 GiB."
  }
}

variable "disk_autoresize_limit" {
  description = "Maximum autoresize size in GiB. Set to 0 for no autoresize limit; it cannot be smaller than disk_size."
  type        = number
  default     = 100

  validation {
    condition     = floor(var.disk_autoresize_limit) == var.disk_autoresize_limit && var.disk_autoresize_limit >= 0 && var.disk_autoresize_limit <= 65536
    error_message = "disk_autoresize_limit must be a whole number between 0 and 65536 GiB."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL database flags, as a map of flag names to string values. Organization baseline flags are applied first and IAM authentication cannot be disabled."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "Additional PostgreSQL databases to create, keyed by database name. The managed postgres database is not recreated."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name in keys(var.databases) : length(name) >= 1 && length(name) <= 63
    ])
    error_message = "Each database name must contain between 1 and 63 characters."
  }
}

variable "iam_users" {
  description = "IAM database principals keyed by full email address. Values must be CLOUD_IAM_USER for people or CLOUD_IAM_SERVICE_ACCOUNT for workloads. No password-based users are created."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for email, principal_type in var.iam_users :
      can(regex("^[^@[:space:]]+@[^@[:space:]]+$", email)) &&
      contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], principal_type)
    ])
    error_message = "iam_users keys must be email addresses and values must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}

variable "backup_start_time" {
  description = "UTC start time for the daily automated backup window, in HH:MM 24-hour format."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a UTC time in HH:MM 24-hour format."
  }
}

variable "backup_retained_backups" {
  description = "Number of most recent automated backups to retain."
  type        = number
  default     = 7

  validation {
    condition     = floor(var.backup_retained_backups) == var.backup_retained_backups && var.backup_retained_backups >= 1 && var.backup_retained_backups <= 365
    error_message = "backup_retained_backups must be a whole number between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of transaction logs retained for point-in-time recovery."
  type        = number
  default     = 7

  validation {
    condition     = floor(var.transaction_log_retention_days) == var.transaction_log_retention_days && var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7
    error_message = "transaction_log_retention_days must be a whole number between 1 and 7."
  }
}

variable "backup_location" {
  description = "Optional region or multi-region in which backups are stored. If null, Cloud SQL uses its default backup location."
  type        = string
  default     = null
  nullable    = true
}

variable "maintenance_day" {
  description = "Day of the maintenance window: 1 is Monday and 7 is Sunday."
  type        = number
  default     = 7

  validation {
    condition     = floor(var.maintenance_day) == var.maintenance_day && var.maintenance_day >= 1 && var.maintenance_day <= 7
    error_message = "maintenance_day must be a whole number from 1 (Monday) through 7 (Sunday)."
  }
}

variable "maintenance_hour" {
  description = "UTC hour at which the maintenance window starts."
  type        = number
  default     = 4

  validation {
    condition     = floor(var.maintenance_hour) == var.maintenance_hour && var.maintenance_hour >= 0 && var.maintenance_hour <= 23
    error_message = "maintenance_hour must be a whole number from 0 through 23."
  }
}

variable "query_string_length" {
  description = "Maximum query string length stored by Query Insights, in bytes."
  type        = number
  default     = 1024

  validation {
    condition     = floor(var.query_string_length) == var.query_string_length && var.query_string_length >= 256 && var.query_string_length <= 4500
    error_message = "query_string_length must be a whole number between 256 and 4500."
  }
}

variable "query_plans_per_minute" {
  description = "Maximum number of query plans captured by Query Insights per minute. Set to 0 to disable plan capture."
  type        = number
  default     = 5

  validation {
    condition     = floor(var.query_plans_per_minute) == var.query_plans_per_minute && var.query_plans_per_minute >= 0 && var.query_plans_per_minute <= 20
    error_message = "query_plans_per_minute must be a whole number between 0 and 20."
  }
}

variable "encryption_key_name" {
  description = "Optional full Cloud KMS key resource name for customer-managed encryption. The Cloud SQL service agent must already be authorized to use the key."
  type        = string
  default     = null
  nullable    = true
}

variable "labels" {
  description = "Additional user labels. The module always sets component=postgresql and managed-by=opentofu."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protect the instance from deletion through both Cloud SQL and OpenTofu. Disable and apply before destroying an instance."
  type        = bool
  default     = true
}
