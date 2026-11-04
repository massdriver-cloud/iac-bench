# ---------------------------------------------------------------------------
# Placement and identity
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Project that hosts the Cloud SQL instance."
  type        = string
}

variable "network_project_id" {
  description = "Project that hosts the apps-<environment> VPC network. Defaults to project_id when null. Set this when the network lives in a Shared VPC host project."
  type        = string
  default     = null
}

variable "region" {
  description = "Region for the instance (for example europe-west1). Must match the region used by the apps network's private services access."
  type        = string
}

variable "environment" {
  description = "Deployment environment. Selects the apps-<environment> VPC network the instance attaches to, and drives environment-specific guardrails."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "instance_name" {
  description = "Name of the Cloud SQL instance. Lowercase letters, digits and hyphens; must start with a letter; max 98 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,97}$", var.instance_name)) && !endswith(var.instance_name, "-")
    error_message = "instance_name must start with a lowercase letter, contain only lowercase letters, digits and hyphens, not end with a hyphen, and be at most 98 characters."
  }
}

variable "labels" {
  description = "Additional labels. Standard labels (environment, managed-by, module) are always applied and take precedence on key conflict."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# DBA-owned sizing and engine decisions
# ---------------------------------------------------------------------------

variable "database_version" {
  description = "PostgreSQL major version, for example POSTGRES_16."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "database_version must be one of POSTGRES_13 through POSTGRES_17."
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
  description = "Machine tier, for example db-custom-2-7680."
  type        = string
  default     = "db-custom-2-7680"

  validation {
    condition     = can(regex("^db-", var.tier))
    error_message = "tier must be a Cloud SQL machine tier starting with db-."
  }
}

variable "availability_type" {
  description = "ZONAL (single zone) or REGIONAL (high availability). Production instances must be REGIONAL; this is enforced by a precondition."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_type" {
  description = "Data disk type."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GB. Storage grows automatically up to disk_autoresize_limit_gb."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "disk_size_gb must be between 10 and 65536."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic storage growth in GB. 0 means no limit."
  type        = number
  default     = 500

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0
    error_message = "disk_autoresize_limit_gb must be 0 or greater."
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
  description = "Maintenance window start hour (UTC), 0 to 23."
  type        = number
  default     = 3

  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23
    error_message = "maintenance_hour must be between 0 and 23."
  }
}

variable "maintenance_track" {
  description = "Maintenance update track: canary or stable."
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["canary", "stable"], var.maintenance_track)
    error_message = "maintenance_track must be canary or stable."
  }
}

variable "backup_start_time" {
  description = "Daily backup window start time, HH:MM in UTC."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in 24-hour format."
  }
}

variable "backup_retained_count" {
  description = "Number of automated backups to retain. Minimum 7 by policy."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retained_count >= 7 && var.backup_retained_count <= 365
    error_message = "backup_retained_count must be between 7 and 365."
  }
}

variable "additional_database_flags" {
  description = "Extra PostgreSQL flags for DBA tuning (for example max_connections, work_mem). Security and logging baseline flags are locked and cannot be set here; see locals.tf."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "Logical database names to create inside the instance."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.databases : can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", d))])
    error_message = "Each database name must start with a letter or underscore, contain only letters, digits and underscores, and be at most 63 characters."
  }
}

# ---------------------------------------------------------------------------
# Access: Google identities only
# ---------------------------------------------------------------------------

variable "iam_principals" {
  description = <<-EOT
    Google identities allowed to connect with IAM database authentication.
    type "user" takes a user email; type "service_account" takes a service account email
    (the .gserviceaccount.com suffix is stripped to form the database role name).
    Grant table- and schema-level privileges inside the database with SQL, as DBAs do today.
  EOT
  type = list(object({
    email = string
    type  = string
  }))
  default = []

  validation {
    condition     = alltrue([for p in var.iam_principals : contains(["user", "service_account"], p.type)])
    error_message = "Each iam_principals entry must have type \"user\" or \"service_account\"."
  }

  validation {
    condition = alltrue([
      for p in var.iam_principals :
      p.type == "user" ? can(regex("^[^@\\s]+@[^@\\s]+$", p.email)) : endswith(p.email, ".gserviceaccount.com")
    ])
    error_message = "user entries need a valid email; service_account entries must end with .gserviceaccount.com."
  }
}
