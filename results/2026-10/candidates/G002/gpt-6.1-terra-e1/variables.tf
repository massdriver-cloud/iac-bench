variable "project_id" {
  description = "Project in which to create the Cloud SQL instance. The SQL Admin API must already be enabled."
  type        = string
}

variable "instance_name" {
  description = "Cloud SQL instance name, unique within the project."
  type        = string
}

variable "region" {
  description = "Region for the instance and its private services access network."
  type        = string
}

variable "private_network" {
  description = "Full VPC self-link or projects/PROJECT/global/networks/NAME. Private services access must already be configured by the network team."
  type        = string
  validation {
    condition     = can(regex("^(https://www.googleapis.com/compute/v1/)?projects/[^/]+/global/networks/[^/]+$", var.private_network))
    error_message = "Use a full VPC self-link or projects/PROJECT/global/networks/NAME."
  }
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version. Choose a version supported in the selected region."
  type        = string
  default     = "POSTGRES_16"
  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version, e.g. POSTGRES_16."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier sized by the DBA."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "REGIONAL for HA, or ZONAL for a single-zone instance."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD size in GiB. Cloud SQL may grow it automatically; it cannot be shrunk."
  type        = number
  default     = 100
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be an integer of at least 10."
  }
}

variable "backup_start_time" {
  description = "Start of the daily backup window in UTC, formatted HH:MM."
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in UTC."
  }
}

variable "retained_backups" {
  description = "Number of automated backups to retain."
  type        = number
  default     = 7
  validation {
    condition     = var.retained_backups >= 7 && var.retained_backups <= 365 && floor(var.retained_backups) == var.retained_backups
    error_message = "retained_backups must be an integer from 7 to 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of transaction logs retained for point-in-time recovery."
  type        = number
  default     = 7
  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7 && floor(var.transaction_log_retention_days) == var.transaction_log_retention_days
    error_message = "transaction_log_retention_days must be an integer from 1 to 7."
  }
}

variable "maintenance_window" {
  description = "Optional weekly maintenance window in UTC. Day is 1 (Monday) through 7 (Sunday); update_track is canary or stable. Null leaves scheduling to Cloud SQL."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string, "stable")
  })
  default = null
  validation {
    condition = var.maintenance_window == null ? true : (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour &&
      contains(["canary", "stable"], var.maintenance_window.update_track)
    )
    error_message = "maintenance_window needs day 1-7, hour 0-23, and update_track canary or stable."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion in OpenTofu and in the Cloud SQL API. Disable explicitly and apply before deleting."
  type        = bool
  default     = true
}

variable "databases" {
  description = "Application databases to create, keyed by database name. Database-level SQL privileges are managed separately."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "Cloud SQL IAM database usernames mapped to CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT. Service-account usernames omit the .gserviceaccount.com suffix. IAM login/connection roles and PostgreSQL grants are managed separately."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for user_type in values(var.iam_users) : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], user_type)])
    error_message = "Each IAM user type must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL flags. IAM authentication, log_connections and log_disconnections are enforced by the module."
  type        = map(string)
  default     = {}
  validation {
    condition     = length(setintersection(toset(keys(var.database_flags)), toset(["cloudsql.iam_authentication", "log_connections", "log_disconnections"]))) == 0
    error_message = "The module controls cloudsql.iam_authentication, log_connections and log_disconnections."
  }
}

variable "labels" {
  description = "Labels to attach to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}
