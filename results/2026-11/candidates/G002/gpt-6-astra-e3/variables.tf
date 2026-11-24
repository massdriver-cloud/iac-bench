variable "project_id" {
  description = "Project in which to create Cloud SQL. Cloud SQL Admin API must already be enabled."
  type        = string
}

variable "instance_name" {
  description = "Cloud SQL instance name; use a new name when replacing a recently deleted instance."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.instance_name))
    error_message = "Use 2-98 lowercase letters, digits or hyphens, beginning with a letter and ending with a letter or digit."
  }
}

variable "region" {
  description = "Region for the instance and its data."
  type        = string
}

variable "private_network" {
  description = "Existing VPC resource ID: projects/NETWORK_PROJECT/global/networks/apps-dev (or apps-staging/apps-prod). A full self-link is also accepted. Private services access must already exist. Supports Shared VPC."
  type        = string
  validation {
    condition     = can(regex("^(https://www.googleapis.com/compute/v1/)?projects/[^/]+/global/networks/[^/]+$", var.private_network))
    error_message = "Supply an existing VPC resource ID or Compute v1 self-link, not a subnetwork."
  }
}

variable "database_version" {
  description = "Explicit PostgreSQL major version, e.g. POSTGRES_16. Verify regional/edition support before upgrading; downgrades are not supported."
  type        = string
  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "Only PostgreSQL engine versions (POSTGRES_<major>) are supported."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier, e.g. db-custom-2-7680. Choose a tier compatible with the edition and availability configuration."
  type        = string
}

variable "edition" {
  description = "Cloud SQL edition, explicitly set to avoid version-dependent API defaults."
  type        = string
  default     = "ENTERPRISE"
  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "Edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "REGIONAL provides cross-zone HA; ZONAL is an explicit cost/resilience tradeoff for nonproduction."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Use REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD size in GB. Storage auto-growth is always enabled; existing disks cannot shrink."
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Disk size must be an integer of at least 10 GB."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Auto-growth ceiling in GB; zero means unlimited. A ceiling can cause an outage when reached."
  type        = number
  default     = 0
  validation {
    condition     = var.disk_autoresize_limit_gb >= 0 && floor(var.disk_autoresize_limit_gb) == var.disk_autoresize_limit_gb
    error_message = "Auto-growth limit must be a nonnegative integer."
  }
}

variable "backup_start_time" {
  description = "Daily automated backup start time in UTC (HH:MM)."
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Use HH:MM in UTC."
  }
}

variable "retained_backups" {
  description = "Number of automated backups retained. Backups cannot be disabled."
  type        = number
  default     = 14
  validation {
    condition     = var.retained_backups >= 7 && var.retained_backups <= 365 && floor(var.retained_backups) == var.retained_backups
    error_message = "Retain an integer between 7 and 365 backups."
  }
}

variable "transaction_log_retention_days" {
  description = "PITR log retention in days. A 1-7 day range is supported across both editions. PITR cannot be disabled."
  type        = number
  default     = 7
  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7 && floor(var.transaction_log_retention_days) == var.transaction_log_retention_days
    error_message = "PITR retention must be an integer between 1 and 7 days."
  }
}

variable "maintenance_window" {
  description = "Maintenance window in UTC; day 1=Monday, 7=Sunday. Stable track by default."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string, "stable")
  })
  default = { day = 7, hour = 4 }
  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour &&
      contains(["stable", "canary"], var.maintenance_window.update_track)
    )
    error_message = "Use day 1-7, hour 0-23 and stable or canary update track."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL flags. IAM authentication is mandatory and cannot be overridden. Flags may require a restart; check version-specific Cloud SQL support."
  type        = map(string)
  default     = {}
  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is managed by this module and cannot be overridden."
  }
}

variable "databases" {
  description = "Application database names; UTF8 encoding. PostgreSQL roles, ownership, schemas and SQL grants are managed separately by DBAs. Do not include the built-in postgres database."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for name in var.databases : can(regex("^[a-z][a-z0-9_]{0,62}$", name)) && !contains(["postgres", "template0", "template1"], name)])
    error_message = "Use non-system lowercase database names of at most 63 characters (letters, digits, underscores)."
  }
}

variable "iam_principals" {
  description = "Map of full Google identity email to USER, SERVICE_ACCOUNT or GROUP. Creates IAM database users and instance-conditioned Cloud SQL client/login IAM grants. Service account emails must include .gserviceaccount.com. Group members must not also be configured as individual users on the same instance."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([for email, kind in var.iam_principals :
      contains(["USER", "SERVICE_ACCOUNT", "GROUP"], kind) &&
      can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", email)) &&
      (kind == "SERVICE_ACCOUNT" ? endswith(email, ".gserviceaccount.com") : !endswith(email, ".gserviceaccount.com"))
    ])
    error_message = "Use full identity emails with type USER, SERVICE_ACCOUNT or GROUP; service accounts must have their full .gserviceaccount.com email."
  }
}

variable "labels" {
  description = "Cloud SQL user labels, e.g. environment, owner and cost_center."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protect the instance in both OpenTofu and the Cloud SQL API. To destroy, explicitly set false and apply first. Also protects managed databases from accidental removal via OpenTofu."
  type        = bool
  default     = true
}
