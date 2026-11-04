# ---------------------------------------------------------------------------
# Identity and placement (no sensible default; must be decided per instance)
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project that hosts the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the Cloud SQL instance. Should match the apps-<env> network's region."
  type        = string
}

variable "instance_name" {
  description = "Name of the Cloud SQL instance."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must be 2-98 chars, lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment. Selects the apps-<environment> VPC and the environment-specific guardrails."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "network_self_link" {
  description = "Self link of the existing apps-<environment> VPC network (owned by the network team). Private services access must already be configured on it. Format: projects/<project>/global/networks/<name>."
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/global/networks/[^/]+$", var.network_self_link))
    error_message = "network_self_link must look like projects/<project>/global/networks/<name>."
  }
}

# ---------------------------------------------------------------------------
# Engine and sizing (DBA decisions)
# ---------------------------------------------------------------------------

variable "database_version" {
  description = "PostgreSQL major version, e.g. POSTGRES_16."
  type        = string

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must look like POSTGRES_<major>, e.g. POSTGRES_16."
  }
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

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680."
  type        = string

  validation {
    condition     = can(regex("^db-", var.tier))
    error_message = "tier must be a Cloud SQL machine tier starting with db-."
  }
}

variable "availability_type" {
  description = "ZONAL (single zone) or REGIONAL (high availability with standby). Prod must be REGIONAL."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GB. Disk autoresize is always on."
  type        = number
  default     = 50

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for disk autoresize in GB. 0 means no limit."
  type        = number
  default     = 500
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS key (CMEK) resource name. null uses Google-managed encryption."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Backup and maintenance (DBA decisions; PITR is always on)
# ---------------------------------------------------------------------------

variable "backup_start_time" {
  description = "Daily backup window start, HH:MM in UTC."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM (24h, UTC)."
  }
}

variable "retained_backups" {
  description = "Number of automated backups to retain. Prod must retain at least 30."
  type        = number
  default     = 14

  validation {
    condition     = var.retained_backups >= 7 && var.retained_backups <= 365
    error_message = "retained_backups must be between 7 and 365."
  }
}

variable "maintenance_day" {
  description = "Maintenance window day of week, 1 (Monday) to 7 (Sunday)."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_day >= 1 && var.maintenance_day <= 7
    error_message = "maintenance_day must be between 1 and 7."
  }
}

variable "maintenance_hour" {
  description = "Maintenance window start hour, 0-23 UTC."
  type        = number
  default     = 3

  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23
    error_message = "maintenance_hour must be between 0 and 23."
  }
}

variable "maintenance_update_track" {
  description = "Maintenance update track: canary or stable."
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["canary", "stable"], var.maintenance_update_track)
    error_message = "maintenance_update_track must be canary or stable."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion. Must be true in prod."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Engine configuration and content
# ---------------------------------------------------------------------------

variable "database_flags" {
  description = "PostgreSQL flags to set, merged over the module defaults. Keys the module locks (see main.tf) cannot be overridden."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "Databases to create on the instance, keyed by database name."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Access: Google identities only. No password-based users are created.
# ---------------------------------------------------------------------------

variable "iam_users" {
  description = "Google identities granted database login via Cloud SQL IAM authentication, keyed by email. type is CLOUD_IAM_USER for people/groups and CLOUD_IAM_SERVICE_ACCOUNT for service accounts."
  type = map(object({
    type = optional(string, "CLOUD_IAM_USER")
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.iam_users : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], v.type)])
    error_message = "Each iam_users type must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}

variable "labels" {
  description = "Additional labels applied to the instance."
  type        = map(string)
  default     = {}
}
