variable "project_id" {
  description = "Project in which to create the Cloud SQL instance. Cloud SQL Admin API must already be enabled."
  type        = string
}

variable "region" {
  description = "Google Cloud region for the instance; choose to match the application location."
  type        = string
}

variable "instance_name" {
  description = "Unique Cloud SQL instance name. Recently deleted names may not be immediately reusable."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.instance_name))
    error_message = "Use 2-98 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Selects the existing apps-dev, apps-staging or apps-prod VPC. Private services access must already exist."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging or prod."
  }
}

variable "network_project_id" {
  description = "Project owning the existing VPC (Shared VPC host project, if used). Defaults to project_id."
  type        = string
  default     = null
}

variable "database_version" {
  description = "DBA-selected Cloud SQL PostgreSQL major version, e.g. POSTGRES_16. Upgrades require an explicit change and review."
  type        = string
  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "Only PostgreSQL versions are supported (POSTGRES_<major>)."
  }
}

variable "tier" {
  description = "DBA-selected Enterprise machine tier, e.g. db-custom-2-7680. Must support the selected version and availability type."
  type        = string
  validation {
    condition     = startswith(var.tier, "db-")
    error_message = "Use a Cloud SQL machine tier starting with db-."
  }
}

variable "availability_type" {
  description = "REGIONAL enables automatic failover across zones; ZONAL is an explicit lower-availability cost choice."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Availability must be REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD capacity in GiB. Automatic growth is enabled; existing disks cannot shrink."
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Disk size must be an integer from 10 to 65536 GiB."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Automatic growth ceiling in GiB; zero means unlimited. Capacity alerts are essential when setting a ceiling."
  type        = number
  default     = 0
  validation {
    condition     = var.disk_autoresize_limit_gb >= 0 && var.disk_autoresize_limit_gb <= 65536 && floor(var.disk_autoresize_limit_gb) == var.disk_autoresize_limit_gb
    error_message = "Growth ceiling must be an integer from 0 to 65536 GiB."
  }
}

variable "database_flags" {
  description = "DBA PostgreSQL tuning flags. Some require restarts. IAM authentication cannot be disabled."
  type        = map(string)
  default     = {}
  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is managed by the module and must not be supplied."
  }
}

variable "backup_start_time" {
  description = "Daily automated backup window start in UTC (HH:MM)."
  type        = string
  default     = "02:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Use a valid 24-hour HH:MM time."
  }
}

variable "backup_location" {
  description = "Optional backup region or multi-region for residency requirements; null uses the service default."
  type        = string
  default     = null
}

variable "retained_backups" {
  description = "Number of daily automated backups retained."
  type        = number
  default     = 14
  validation {
    condition     = var.retained_backups >= 1 && var.retained_backups <= 365 && floor(var.retained_backups) == var.retained_backups
    error_message = "Retain an integer number of backups between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "PITR log retention in days (Enterprise supports 1-7)."
  type        = number
  default     = 7
  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7 && floor(var.transaction_log_retention_days) == var.transaction_log_retention_days
    error_message = "PITR log retention must be an integer between 1 and 7 days."
  }
}

variable "maintenance_window" {
  description = "Maintenance timing in UTC: day 1=Monday through 7=Sunday, hour 0-23, rollout track stable or canary."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string, "stable")
  })
  default = {
    day  = 7
    hour = 4
  }
  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour &&
      contains(["stable", "canary"], var.maintenance_window.update_track)
    )
    error_message = "Choose day 1-7, hour 0-23 and update_track stable or canary."
  }
}

variable "databases" {
  description = "Databases to create, keyed by name. Encoding and collation changes can be destructive. The built-in postgres database is not managed."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
  validation {
    condition     = alltrue([for name in keys(var.databases) : length(name) > 0 && !contains(["postgres", "template0", "template1"], name)])
    error_message = "Database names cannot be empty or reserved PostgreSQL database names."
  }
}

variable "iam_members" {
  description = "IAM database access, keyed by full lowercase Google identity email; values are USER, SERVICE_ACCOUNT or GROUP. Creates SQL IAM users and grants instance-scoped login/client access. Does not grant SQL object privileges."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([for email, kind in var.iam_members :
      contains(["USER", "SERVICE_ACCOUNT", "GROUP"], kind) &&
      can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", email)) && email == lower(email) &&
      (kind == "SERVICE_ACCOUNT" ? endswith(email, ".gserviceaccount.com") : !endswith(email, ".gserviceaccount.com"))
    ])
    error_message = "Use lowercase identity emails and USER, SERVICE_ACCOUNT or GROUP; service accounts must end in .gserviceaccount.com."
  }
}

variable "deletion_protection" {
  description = "Protect both OpenTofu deletion and API deletion. Disable explicitly and apply before an intentional teardown."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional Cloud SQL labels. The environment and managed_by labels are reserved."
  type        = map(string)
  default     = {}
}
