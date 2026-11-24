variable "project_id" {
  description = "Project that owns the Cloud SQL instance. Cloud SQL Admin API must already be enabled."
  type        = string
}

variable "name" {
  description = "Cloud SQL instance name; must be unique in the project, including recently deleted instances."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.name))
    error_message = "Use 2-98 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "region" {
  description = "Region of the instance; choose near application workloads."
  type        = string
}

variable "environment" {
  description = "Application environment; the existing VPC must be named apps-<environment>."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging or prod."
  }
}

variable "network_project_id" {
  description = "Project owning the existing apps-<environment> VPC and its private services access (may be a Shared VPC host project)."
  type        = string
}

variable "postgres_version" {
  description = "Explicit supported PostgreSQL major version, e.g. POSTGRES_16. Changing major version is an upgrade, not a routine setting change."
  type        = string
  validation {
    condition     = can(regex("^POSTGRES_(14|15|16|17|18)$", var.postgres_version))
    error_message = "Choose POSTGRES_14 through POSTGRES_18, subject to regional Cloud SQL support."
  }
}

variable "tier" {
  description = "Cloud SQL Enterprise machine tier, e.g. db-custom-2-7680. DBAs own capacity sizing."
  type        = string
}

variable "availability_type" {
  description = "ZONAL or REGIONAL (HA). Production requires REGIONAL."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "Choose ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD capacity in GB; can grow but cannot shrink. Storage auto-resizes without a fixed cap."
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Disk size must be a whole number of at least 10 GB."
  }
}

variable "database_flags" {
  description = "DBA-owned PostgreSQL tuning flags. IAM database authentication is mandatory and cannot be overridden. Some flags restart the instance."
  type        = map(string)
  default     = {}
  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is managed by this module."
  }
}

variable "databases" {
  description = "Databases to create, keyed by name. SQL grants, schemas, extensions and ownership are managed separately by DBAs."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "iam_users" {
  description = "Google user email addresses to register for IAM database authentication. No passwords are created."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for email in var.iam_users : can(regex("^[^@ ]+@[^@ ]+$", email)) && !endswith(email, ".gserviceaccount.com")])
    error_message = "Supply user email addresses, not service account addresses."
  }
}

variable "iam_service_accounts" {
  description = "Full service account emails to register for IAM database authentication. The database username omits .gserviceaccount.com."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for email in var.iam_service_accounts : can(regex("^[^@ ]+@[^@ ]+\\.gserviceaccount\\.com$", email))])
    error_message = "Supply full service account email addresses."
  }
}

variable "iam_groups" {
  description = "Cloud Identity group emails to register for IAM group database authentication. Do not also list individual members in iam_users/iam_service_accounts."
  type        = set(string)
  default     = []
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC: day 1=Monday through 7=Sunday, hour 0-23. Stable update track is used."
  type = object({
    day  = number
    hour = number
  })
  default = { day = 7, hour = 3 }
  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day && var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour
    error_message = "Use integer day 1-7 and integer hour 0-23."
  }
}

variable "backup_start_time" {
  description = "Daily backup window start in UTC, HH:MM."
  type        = string
  default     = "01:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Use a valid UTC HH:MM time."
  }
}

variable "backup_retention_count" {
  description = "Number of daily automated backups to retain. PITR transaction logs are independently retained for seven days."
  type        = number
  default     = 14
  validation {
    condition     = var.backup_retention_count >= 7 && var.backup_retention_count <= 365 && floor(var.backup_retention_count) == var.backup_retention_count
    error_message = "Retain 7-365 backups, as a whole number."
  }
}

variable "deletion_protection" {
  description = "Protect deletion in both OpenTofu and the Cloud SQL API. Explicitly set false and apply before intentional destruction."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional Cloud SQL labels. The environment and managed_by labels are reserved."
  type        = map(string)
  default     = {}
}
