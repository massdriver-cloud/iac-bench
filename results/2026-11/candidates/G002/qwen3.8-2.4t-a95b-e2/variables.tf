# ---------------------------------------------------------------------------
# Required: the four things that define WHERE and WHAT this instance is.
# Everything else has a deliberate default.
# ---------------------------------------------------------------------------

variable "project" {
  description = "GCP project the Cloud SQL instance is created in."
  type        = string

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project))
    error_message = "Project ID must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits and hyphens."
  }
}

variable "name" {
  description = "Instance name. Immutable, must be unique within the project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "Instance name must be 2-63 characters, start with a lowercase letter, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Selects the Private Service Access network owned by the network team: apps-dev, apps-staging or apps-prod. This is the only networking decision."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "GCP region for the instance (e.g. us-central1)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must look like a GCP region, e.g. us-central1 or europe-west4."
  }
}

# ---------------------------------------------------------------------------
# DBA decisions: sizing, version, availability, retention, tuning, and the
# identities that get initial database access. All optional, all defaulted.
# ---------------------------------------------------------------------------

variable "database_version" {
  description = "PostgreSQL major version. Defaults to the team standard; override only when an application genuinely requires otherwise."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "Supported versions are POSTGRES_13 through POSTGRES_17."
  }
}

variable "tier" {
  description = "Machine shape. Default is a modest custom shape (1 vCPU / 3.75 GB); use db-custom-<vcpu>-<mem_mb> or a predefined tier to change it."
  type        = string
  default     = "db-custom-1-3840"

  validation {
    condition     = can(regex("^db-[a-z0-9-]+$", var.tier))
    error_message = "Tier must be a Cloud SQL machine type, e.g. db-custom-2-7680."
  }
}

variable "availability_type" {
  description = "REGIONAL runs a synchronous standby in a second zone (high availability); ZONAL does not. REGIONAL is the default everywhere and ZONAL is only ever allowed outside prod."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Availability type must be REGIONAL or ZONAL."
  }

  validation {
    condition     = var.environment != "prod" || var.availability_type == "REGIONAL"
    error_message = "Production databases must be REGIONAL (highly available). ZONAL is a cost trade-off permitted only in dev and staging."
  }
}

variable "disk_size_gb" {
  description = "Starting data disk size in GB. Storage auto-resizes upward from this value, so treat it as a starting point rather than a capacity plan."
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "Disk size must be between 10 and 65536 GB."
  }
}

variable "backup_retention_days" {
  description = "Number of daily backups retained (1-35). Point-in-time recovery is always enabled in addition."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

variable "deletion_protection" {
  description = "Prevents the instance from being destroyed via OpenTofu. Defaults to true and can never be disabled in prod."
  type        = bool
  default     = true

  validation {
    condition     = var.environment != "prod" || var.deletion_protection
    error_message = "deletion_protection cannot be disabled for prod instances."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL database flags the DBAs own (e.g. work_mem, max_connections). Locked flags set by the module (IAM authentication, connection logging) cannot be overridden."
  type        = map(string)
  default     = {}

  validation {
    condition     = length(setintersection(keys(var.database_flags), ["cloudsql.iam_authentication", "log_connections", "log_disconnections"])) == 0
    error_message = "cloudsql.iam_authentication, log_connections and log_disconnections are locked by this module and cannot be set here."
  }
}

variable "iam_database_users" {
  description = "Google identities (user or service account emails) to create as database users so they can sign in with IAM database authentication. The module never creates password users."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_database_users : can(regex("^[^@]+@.+$", u))])
    error_message = "Each IAM database user must be a Google principal email address."
  }
}

variable "labels" {
  description = "Additional resource labels (e.g. owner, application). The labels 'env' and 'managed-by' are applied by the module and cannot be overridden."
  type        = map(string)
  default     = {}

  validation {
    condition     = length(setintersection(keys(var.labels), ["env", "managed-by"])) == 0
    error_message = "The labels 'env' and 'managed-by' are managed by this module and cannot be set here."
  }
}

variable "encryption_key_name" {
  description = "Cloud KMS CryptoKey self-link for customer-managed encryption of the instance. Leave unset for Google-managed encryption."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of the Private Service Access allocated range to place the instance in, only needed when the apps-<environment> network has more than one. Leave unset otherwise."
  type        = string
  default     = null
}

variable "network_project" {
  description = "Project that owns the apps-<environment> network, if it is not the same project as the instance. Defaults to var.project."
  type        = string
  default     = null
}
