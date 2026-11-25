############################################################
# Identity / placement
############################################################

variable "project_id" {
  description = "GCP project in which the Cloud SQL instance is created."
  type        = string
}

variable "name" {
  description = "Cloud SQL instance name. Must be unique in the project and cannot be reused for ~1 week after deletion."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.name))
    error_message = "name must start with a letter, contain only lowercase letters, digits and hyphens, and be at most 98 characters."
  }
}

variable "environment" {
  description = "Environment this instance serves. Selects the VPC (apps-<environment>) and the environment-specific guardrails."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Region for the instance (e.g. europe-west1)."
  type        = string
}

variable "network_project_id" {
  description = "Project that hosts the apps-<environment> VPC (the network team's host project). Defaults to project_id."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of the private-services-access range to allocate the instance IP from. Leave null to let Cloud SQL pick the range the network team configured."
  type        = string
  default     = null
}

############################################################
# Engine and sizing (DBA decisions)
############################################################

variable "database_version" {
  description = "PostgreSQL major version, as a Cloud SQL version string."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a PostgreSQL version such as POSTGRES_16."
  }
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-8192 (2 vCPU, 8 GiB) or db-perf-optimized-N-4 for ENTERPRISE_PLUS."
  type        = string
  default     = "db-custom-2-8192"
}

variable "edition" {
  description = "Cloud SQL edition."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "ZONAL or REGIONAL (HA). Defaults to REGIONAL in prod and ZONAL elsewhere. prod cannot be ZONAL."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["ZONAL", "REGIONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GiB. The disk grows automatically; this is only the starting point."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic disk growth in GiB. 0 means no limit."
  type        = number
  default     = 0
}

variable "disk_type" {
  description = "Data disk type."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be PD_SSD, PD_HDD or HYPERDISK_BALANCED."
  }
}

variable "data_cache_enabled" {
  description = "Enable the local SSD data cache (ENTERPRISE_PLUS only; ignored otherwise)."
  type        = bool
  default     = true
}

variable "database_flags" {
  description = <<-EOT
    PostgreSQL / Cloud SQL flags owned by the DBA team, as name => value.
    Flags that the module enforces (IAM authentication, connection/disconnection logging, etc.)
    cannot be overridden here.
  EOT
  type        = map(string)
  default     = {}
}

############################################################
# Backups, maintenance, protection
############################################################

variable "backup_start_time" {
  description = "Daily automated backup window start, HH:MM in UTC."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM (24h, UTC)."
  }
}

variable "backup_location" {
  description = "Multi-region or region to store backups in (e.g. eu, us). null uses the instance's default."
  type        = string
  default     = null
}

variable "retained_backups" {
  description = "Number of daily automated backups to retain."
  type        = number
  default     = 14

  validation {
    condition     = var.retained_backups >= 7 && var.retained_backups <= 365
    error_message = "retained_backups must be between 7 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of write-ahead logs retained for point-in-time recovery (1-35)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance window. day: 1 (Monday) - 7 (Sunday); hour: 0-23 UTC; update_track: stable or canary."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 &&
      contains(["stable", "canary", "week5"], var.maintenance_window.update_track)
    )
    error_message = "maintenance_window.day must be 1-7, hour 0-23 and update_track one of stable, canary, week5."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion (both at the API and in OpenTofu). Always on in prod."
  type        = bool
  default     = true
}

variable "kms_key_name" {
  description = "Cloud KMS key (projects/.../cryptoKeys/...) for customer-managed encryption. null uses Google-managed keys."
  type        = string
  default     = null
}

############################################################
# Databases and access
############################################################

variable "databases" {
  description = "Databases to create on the instance, keyed by name. charset/collation are optional."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "iam_users" {
  description = <<-EOT
    Google identities allowed to log in to this instance, as e-mail addresses (users, groups via
    their members, or service accounts). Each gets a Cloud SQL IAM database user plus the IAM roles
    needed to connect to this instance only. Database-level privileges (GRANT ...) remain a DBA task.
  EOT
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@]+@[^@]+$", u))])
    error_message = "iam_users must be e-mail addresses."
  }
}

variable "connector_enforcement" {
  description = "Set to REQUIRED to only allow connections through the Cloud SQL Auth Proxy / language connectors."
  type        = string
  default     = "NOT_REQUIRED"

  validation {
    condition     = contains(["NOT_REQUIRED", "REQUIRED"], var.connector_enforcement)
    error_message = "connector_enforcement must be NOT_REQUIRED or REQUIRED."
  }
}

variable "labels" {
  description = "Additional labels applied to the instance."
  type        = map(string)
  default     = {}
}
