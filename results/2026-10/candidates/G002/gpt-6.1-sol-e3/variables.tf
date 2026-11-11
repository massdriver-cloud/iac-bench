variable "project_id" {
  description = "Google Cloud project for the instance. Credentials come from Application Default Credentials."
  type        = string
}

variable "region" {
  description = "DBA-selected region for application locality and data residency."
  type        = string
}

variable "instance_name" {
  description = "Cloud SQL instance name; deleted names cannot immediately be reused."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.instance_name))
    error_message = "Use a 2-98 character lowercase name, starting with a letter and ending with a letter or digit."
  }
}

variable "network_self_link" {
  description = "Full self-link of the existing apps-dev, apps-staging or apps-prod VPC, including its host project for Shared VPC. Private services access must already exist."
  type        = string
  validation {
    condition     = can(regex("^https://www.googleapis.com/compute/v1/projects/[^/]+/global/networks/apps-(dev|staging|prod)$", var.network_self_link))
    error_message = "Supply the full self-link of the existing apps-dev, apps-staging or apps-prod network."
  }
}

variable "postgres_version" {
  description = "Explicit PostgreSQL major version. Upgrades require DBA review of Cloud SQL prerequisites."
  type        = string
  validation {
    condition     = contains(["POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17", "POSTGRES_18"], var.postgres_version)
    error_message = "Choose a supported PostgreSQL major: POSTGRES_14 through POSTGRES_18."
  }
}

variable "tier" {
  description = "DBA-selected Cloud SQL Enterprise machine tier, e.g. db-custom-2-7680; must support the selected availability."
  type        = string
  validation {
    condition     = startswith(var.tier, "db-")
    error_message = "Supply a Cloud SQL machine tier beginning with db-."
  }
}

variable "availability_type" {
  description = "REGIONAL provides a cross-zone standby; ZONAL is an explicit cost/availability tradeoff."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Availability must be REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial/minimum SSD size in GB. Automatic growth is always enabled; disks cannot shrink."
  type        = number
  default     = 10
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Disk size must be an integer of at least 10 GB."
  }
}

variable "backup_start_time" {
  description = "Daily UTC backup window start, HH:MM. Backups and PITR cannot be disabled."
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Use a UTC HH:MM time."
  }
}

variable "retained_backups" {
  description = "Daily backups to retain, at least seven."
  type        = number
  default     = 14
  validation {
    condition     = var.retained_backups >= 7 && var.retained_backups <= 365 && floor(var.retained_backups) == var.retained_backups
    error_message = "Retain an integer between 7 and 365 backups."
  }
}

variable "pitr_days" {
  description = "Transaction log retention for point-in-time recovery (Enterprise supports 1-7 days)."
  type        = number
  default     = 7
  validation {
    condition     = var.pitr_days >= 1 && var.pitr_days <= 7 && floor(var.pitr_days) == var.pitr_days
    error_message = "PITR retention must be an integer from 1 to 7."
  }
}

variable "maintenance_window" {
  description = "Weekly UTC maintenance window: day 1=Monday through 7=Sunday, hour 0-23; stable or canary track."
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
    error_message = "Use a day from 1-7, hour from 0-23 and stable/canary track."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL tuning flags. Mandatory IAM, connection logging and pgAudit flags cannot be overridden. Flag changes may restart the instance."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for flag in keys(var.database_flags) :
      !contains(["cloudsql.iam_authentication", "cloudsql.enable_pgaudit", "pgaudit.log", "log_connections", "log_disconnections"], flag)
    ])
    error_message = "IAM authentication and audit baseline flags are managed by the module and cannot be overridden."
  }
}

variable "databases" {
  description = "Application databases to create. System databases are not managed. SQL schemas, object grants and migrations remain the DBA's responsibility."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for name in var.databases : length(name) > 0 && length(name) <= 63 && !contains(["postgres", "template0", "template1"], name)])
    error_message = "Database names must be 1-63 characters and must not name a built-in database."
  }
}

variable "iam_principals" {
  description = "Map of full Google identity email to IAM_USER, IAM_SERVICE_ACCOUNT or IAM_GROUP. Creates database identities and instance-scoped connector/login IAM grants. SQL privileges are separate."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for email, kind in var.iam_principals :
      can(regex("^[^@\\s]+@[^@\\s]+$", email)) && email == lower(email) &&
      contains(["IAM_USER", "IAM_SERVICE_ACCOUNT", "IAM_GROUP"], kind) &&
      (kind != "IAM_SERVICE_ACCOUNT" || endswith(email, ".gserviceaccount.com"))
    ])
    error_message = "Use lowercase Google identity emails with IAM_USER, IAM_SERVICE_ACCOUNT or IAM_GROUP; service accounts must end in .gserviceaccount.com."
  }
}

variable "labels" {
  description = "Ownership, environment and cost labels; must satisfy Google Cloud label constraints."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "OpenTofu and API instance deletion protection. To delete, first set false and apply, then destroy."
  type        = bool
  default     = true
}
