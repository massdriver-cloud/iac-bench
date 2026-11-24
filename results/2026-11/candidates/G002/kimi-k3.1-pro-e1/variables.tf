variable "project_id" {
  description = "ID of the Google Cloud project in which the Cloud SQL instance is created. The VPC may belong to a different Shared VPC host project."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for the instance, for example us-central1."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a Google Cloud region such as us-central1."
  }
}

variable "instance_name" {
  description = "Name of the Cloud SQL instance. Instance names cannot be changed after creation."
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.instance_name) <= 98 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.instance_name))
    )
    error_message = "instance_name must be at most 98 characters, start with a letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. This selects the matching apps-<environment> VPC and defaults production to regional availability."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, or prod."
  }
}

variable "network_self_link" {
  description = "Self link or resource ID of the existing apps-<environment> VPC. Private services access must already be configured by the network team."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(regex("/global/networks/[a-z][a-z0-9-]*$", var.network_self_link)) ||
      can(regex("^projects/[^/]+/global/networks/[a-z][a-z0-9-]*$", var.network_self_link))
    )
    error_message = "network_self_link must be a VPC self link or a resource ID like projects/PROJECT/global/networks/NETWORK."
  }
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version. Upgrades and version selection remain a DBA decision."
  type        = string
  default     = "POSTGRES_16"
  nullable    = false

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+(_[0-9]+)?$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version such as POSTGRES_16."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier, for example db-custom-2-7680."
  type        = string
  default     = "db-custom-2-7680"
  nullable    = false

  validation {
    condition     = length(trimspace(var.tier)) > 0
    error_message = "tier must not be empty."
  }
}

variable "edition" {
  description = "Cloud SQL edition. Use ENTERPRISE_PLUS only with a compatible tier and PostgreSQL version."
  type        = string
  default     = "ENTERPRISE"
  nullable    = false

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "ZONAL or REGIONAL. If unset, production is REGIONAL and other environments are ZONAL."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL, REGIONAL, or null."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD/HDD data disk size in GiB. Automatic storage growth is always enabled."
  type        = number
  default     = 20
  nullable    = false

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_type" {
  description = "Persistent disk type. PD_SSD is the standard for database workloads."
  type        = string
  default     = "PD_SSD"
  nullable    = false

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum automatically grown disk size in GiB. Zero means no module-imposed limit; the initial disk size still applies."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0
    error_message = "disk_autoresize_limit_gb must be zero or greater."
  }
}

variable "deletion_protection" {
  description = "Prevent deletion through the Cloud SQL API and OpenTofu. Disable deliberately before destroying an instance."
  type        = bool
  default     = true
  nullable    = false
}

variable "labels" {
  description = "Additional resource labels. Standard managed-by, component, and environment labels take precedence over conflicting keys."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "databases" {
  description = <<-EOT
    Additional PostgreSQL databases, keyed by database name. Cloud SQL's system databases
    are not managed here. Charset defaults to UTF8; collation can be set when required.
  EOT
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string)
  }))
  default  = {}
  nullable = false
}

variable "iam_users" {
  description = <<-EOT
    IAM database principals keyed by their full identity email. Values must be
    CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT. PostgreSQL uses the complete
    service-account email as its username. Database role grants are intentionally
    left to the DBA team's SQL migration process.
  EOT
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for principal_type in values(var.iam_users) :
      contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], principal_type)
    ])
    error_message = "Every iam_users value must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }

  validation {
    condition = alltrue([
      for identity in keys(var.iam_users) : can(regex("^[^@[:space:]]+@[^@[:space:]]+$", identity))
    ])
    error_message = "Every iam_users key must be a full IAM identity email address."
  }
}

variable "database_flags" {
  description = <<-EOT
    Additional or overriding PostgreSQL database flags. The module's connection
    logging defaults can be overridden here. cloudsql.iam_authentication is a
    mandatory control and is always forced to on.
  EOT
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "backup_start_time" {
  description = "UTC start time for the automated backup window, in 24-hour HH:MM format."
  type        = string
  default     = "03:00"
  nullable    = false

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a UTC time in HH:MM format."
  }
}

variable "backup_location" {
  description = "Optional Google Cloud region or multi-region in which backups are stored. Null uses Cloud SQL's default."
  type        = string
  default     = null
}

variable "retained_backups" {
  description = "Number of automated backups retained by Cloud SQL."
  type        = number
  default     = 35
  nullable    = false

  validation {
    condition     = var.retained_backups >= 1 && var.retained_backups <= 365
    error_message = "retained_backups must be between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of transaction logs retained for point-in-time recovery (Cloud SQL supports 1 through 7)."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition = (
      var.transaction_log_retention_days >= 1 &&
      var.transaction_log_retention_days <= 7 &&
      floor(var.transaction_log_retention_days) == var.transaction_log_retention_days
    )
    error_message = "transaction_log_retention_days must be a whole number between 1 and 7."
  }
}

variable "maintenance_day" {
  description = "Day of week for maintenance: 1 is Monday and 7 is Sunday."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition = (
      var.maintenance_day >= 1 && var.maintenance_day <= 7 &&
      floor(var.maintenance_day) == var.maintenance_day
    )
    error_message = "maintenance_day must be a whole number from 1 (Monday) through 7 (Sunday)."
  }
}

variable "maintenance_hour" {
  description = "UTC hour at which the maintenance window starts (0 through 23)."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition = (
      var.maintenance_hour >= 0 && var.maintenance_hour <= 23 &&
      floor(var.maintenance_hour) == var.maintenance_hour
    )
    error_message = "maintenance_hour must be a whole number from 0 through 23."
  }
}

variable "maintenance_update_track" {
  description = "Maintenance update track; stable is the conservative fleet standard."
  type        = string
  default     = "stable"
  nullable    = false

  validation {
    condition     = contains(["stable", "canary", "week5"], var.maintenance_update_track)
    error_message = "maintenance_update_track must be stable, canary, or week5."
  }
}
