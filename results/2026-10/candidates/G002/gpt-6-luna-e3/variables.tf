variable "project_id" {
  description = "Google Cloud project that owns the Cloud SQL instance."
  type        = string
  nullable    = false
}

variable "instance_name" {
  description = "Globally unique Cloud SQL instance name within the project."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must be 2-98 characters, start with a lowercase letter, and contain only lowercase letters, digits, or hyphens."
  }
}

variable "region" {
  description = "Region in which to create the instance."
  type        = string
  nullable    = false
}

variable "network_self_link" {
  description = "Self-link of the environment VPC. Private services access must already be configured on this network."
  type        = string
  nullable    = false
}

variable "database_name" {
  description = "Initial PostgreSQL database to create on the instance."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain at most 63 letters, digits, underscores, or hyphens."
  }
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "database_version must be a supported PostgreSQL major version (POSTGRES_14 through POSTGRES_17)."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier. Choose an appropriately sized supported tier for the workload."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "Availability configuration. REGIONAL provides a standby in another zone; ZONAL is lower cost."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL."
  }
}

variable "deletion_protection" {
  description = "Protect this instance from accidental deletion. Set false deliberately before retiring an instance."
  type        = bool
  default     = true
}

variable "disk_size_gb" {
  description = "Initial SSD data disk size in GiB. The disk is configured to grow automatically."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "disk_size_gb must be between 10 and 65536 GiB."
  }
}

variable "backup_start_time" {
  description = "Daily backup start time in UTC, HH:MM format."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a valid UTC time in HH:MM format."
  }
}

variable "maintenance_day" {
  description = "Preferred maintenance day: 1=Monday through 7=Sunday."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_day >= 1 && var.maintenance_day <= 7 && floor(var.maintenance_day) == var.maintenance_day
    error_message = "maintenance_day must be an integer from 1 (Monday) through 7 (Sunday)."
  }
}

variable "maintenance_hour" {
  description = "Preferred maintenance start hour in UTC (0-23)."
  type        = number
  default     = 4

  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23 && floor(var.maintenance_hour) == var.maintenance_hour
    error_message = "maintenance_hour must be an integer from 0 through 23."
  }
}

variable "database_flags" {
  description = "PostgreSQL database flags keyed by flag name. IAM database authentication is enabled by this module and must not be overridden here."
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "Do not set cloudsql.iam_authentication; this module manages that flag."
  }
}

variable "iam_users" {
  description = "Google identities to provision as Cloud SQL IAM database users. Grant their required Cloud SQL IAM roles separately according to organizational policy."
  type = map(object({
    email = string
    type  = string # CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT
  }))
  default = {}

  validation {
    condition = alltrue([
      for user in values(var.iam_users) : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], user.type)
    ])
    error_message = "Each iam_users entry type must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}

variable "labels" {
  description = "Additional labels applied to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}
