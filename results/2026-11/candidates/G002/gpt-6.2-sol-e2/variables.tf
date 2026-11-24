variable "environment" {
  description = "Environment of the existing application VPC: dev, staging, or prod."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "instance_name" {
  description = "Cloud SQL instance ID, unique in the provider project."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.instance_name))
    error_message = "instance_name must be 1–98 characters, start with a lowercase letter, and end with a lowercase letter or digit; interior hyphens are allowed."
  }
}

variable "region" {
  description = "Google Cloud region for the database instance."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+(-[a-z]+)+[0-9]+$", var.region))
    error_message = "region must be a Google Cloud region such as us-central1."
  }
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL version identifier, for example POSTGRES_16. Choose a version supported by the selected edition and region."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+(_[0-9]+)?$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version identifier such as POSTGRES_16."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier compatible with the selected edition, version, and region."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^db-[a-z0-9]+(-[a-z0-9]+)*$", var.tier))
    error_message = "tier must be a Cloud SQL machine tier such as db-custom-2-7680."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS."
  type        = string
  default     = "ENTERPRISE"
  nullable    = false

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "Override the availability topology with ZONAL or REGIONAL. Defaults to REGIONAL in prod and ZONAL elsewhere."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null ? true : contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL when specified."
  }
}

variable "initial_disk_size_gb" {
  description = "Initial SSD capacity in GB. Cloud SQL automatically expands it; changes to this input do not resize an existing disk."
  type        = number
  default     = 10
  nullable    = false

  validation {
    condition     = var.initial_disk_size_gb >= 10 && floor(var.initial_disk_size_gb) == var.initial_disk_size_gb
    error_message = "initial_disk_size_gb must be a whole number of at least 10."
  }
}

variable "maintenance_window" {
  description = "Optional UTC maintenance window; day 1 is Monday, day 7 is Sunday."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string, "stable")
  })
  default = null

  validation {
    condition = var.maintenance_window == null ? true : try(
      contains(range(1, 8), var.maintenance_window.day) &&
      contains(range(24), var.maintenance_window.hour) &&
      contains(["canary", "stable", "week5"], var.maintenance_window.update_track), false
    )
    error_message = "maintenance_window must specify an integer day (1–7), integer hour (0–23), and update_track of canary, stable, or week5."
  }
}

variable "database_flags" {
  description = "Extra PostgreSQL flags supported by Cloud SQL for the chosen version; module-managed IAM and connection logging flags cannot be set here."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for key, value in var.database_flags : value != null &&
      !contains(["cloudsql.iam_authentication", "log_connections", "log_disconnections"], lower(key))
    ])
    error_message = "database_flags must have non-null values and cannot set cloudsql.iam_authentication, log_connections, or log_disconnections."
  }
}

variable "databases" {
  description = "Application databases keyed by PostgreSQL database name, with optional creation-time charset and collation."
  type = map(object({
    charset   = optional(string)
    collation = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for name, config in var.databases : config != null && can(regex("^[A-Za-z0-9_-]{1,63}$", name)) &&
      !contains(["postgres", "template0", "template1", "cloudsqladmin"], lower(name))
    ])
    error_message = "Use non-system database names of 1–63 ASCII letters, digits, underscores, or hyphens, and provide an object (possibly empty) for each."
  }
}

variable "iam_user_emails" {
  description = "Google user email addresses to register as Cloud SQL IAM database users and grant instance-scoped access."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for email in var.iam_user_emails : try(length(email) <= 63 &&
        can(regex("^[a-z0-9._%+!-]+@[a-z0-9.-]+\\.[a-z0-9-]+$", email)) &&
      !endswith(email, ".gserviceaccount.com"), false)
    ])
    error_message = "iam_user_emails must contain lowercase user email addresses of at most 63 ASCII characters, not service account addresses."
  }
}

variable "iam_service_account_emails" {
  description = "Full Google service account emails to register as Cloud SQL IAM database users and grant instance-scoped access."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for email in var.iam_service_account_emails : try(
        can(regex("^[a-z0-9_-]+@[a-z0-9.-]+\\.gserviceaccount\\.com$", email)) &&
      length(trimsuffix(email, ".gserviceaccount.com")) <= 63, false)
    ])
    error_message = "Use full lowercase service account emails ending in .gserviceaccount.com whose PostgreSQL usernames (after stripping that suffix) fit within 63 characters."
  }
}

variable "labels" {
  description = "Additional Cloud SQL labels. The module controls the environment and managed-by labels."
  type        = map(string)
  default     = {}
  nullable    = false
}
