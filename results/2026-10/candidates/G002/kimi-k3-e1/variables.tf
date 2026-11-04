# ============================================================================
# Decisions that belong to the calling DBA — every instance supplies these.
# ============================================================================

variable "name" {
  description = "Cloud SQL instance name (lowercase letters, digits and hyphens, starting with a letter, max 98 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,97}$", var.name))
    error_message = "name must be 1-98 chars of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "project_id" {
  description = "ID of the GCP project that owns the instance."
  type        = string

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "Region the instance runs in, e.g. \"europe-west1\"."
  type        = string
}

variable "network" {
  description = "VPC network the instance is attached to via private services access. Accepts a bare network name (\"apps-dev\", resolved in var.project_id), a partial path (\"projects/<p>/global/networks/<n>\", e.g. for a Shared VPC host project) or a full self-link URL. Private services access must already be configured on the network — the network team owns it and has done this."
  type        = string

  validation {
    condition     = length(var.network) > 0
    error_message = "network must not be empty."
  }
}

variable "tier" {
  description = "Machine tier of the instance, e.g. \"db-custom-2-7680\" (ENTERPRISE) or \"db-perf-optimized-N-2\" (ENTERPRISE_PLUS). Size it per workload."
  type        = string
}

# ============================================================================
# DBA-owned decisions with sensible module defaults.
# ============================================================================

variable "database_version" {
  description = "PostgreSQL engine version, e.g. \"POSTGRES_16\"."
  type        = string
  default     = "POSTGRES_16"
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "ZONAL for a single-zone instance, REGIONAL for HA with a standby in another zone. Use REGIONAL for production."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_type" {
  description = "Storage type: PD_SSD, PD_HDD or HYPERDISK_BALANCED (ENTERPRISE_PLUS only)."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be PD_SSD, PD_HDD or HYPERDISK_BALANCED."
  }
}

variable "disk_size_gb" {
  description = "Initial storage size in GB. Storage autoresize is always on, so this is a floor, not a ceiling."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum size in GB storage autoresize may grow to. 0 (default) means no limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0
    error_message = "disk_autoresize_limit_gb must be >= 0."
  }
}

variable "database_flags" {
  description = "PostgreSQL configuration flags (name => value), e.g. { \"max_connections\" = \"500\" }. The module always forces cloudsql.iam_authentication = on; a caller-supplied value cannot turn it off."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "Application databases to create, keyed by database name. Charset and collation are optional per database."
  type = map(object({
    charset   = optional(string)
    collation = optional(string)
  }))
  default = {}
}

variable "iam_users" {
  description = "Google identity emails (people) to create as CLOUD_IAM_USER database logins. The principals also need roles/cloudsql.instanceUser, granted via the organization's IAM tooling. Grant PostgreSQL roles to them inside the database afterwards."
  type        = set(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "Service account emails (workloads) to create as CLOUD_IAM_SERVICE_ACCOUNT database logins. The \".gserviceaccount.com\" suffix is stripped automatically, as Cloud SQL requires. The principals also need roles/cloudsql.instanceUser, granted via the organization's IAM tooling."
  type        = set(string)
  default     = []
}

# ============================================================================
# Organization-wide standards — overridable, but the defaults ARE the standard.
# ============================================================================

variable "backup" {
  description = "Automated backup and point-in-time recovery policy."
  type = object({
    enabled                        = optional(bool, true)
    start_time                     = optional(string, "02:00") # UTC, HH:MM
    point_in_time_recovery         = optional(bool, true)
    transaction_log_retention_days = optional(number, 7)
    retained_backups               = optional(number, 7)
  })
  default = {}

  validation {
    condition     = var.backup.enabled || !var.backup.point_in_time_recovery
    error_message = "point_in_time_recovery requires backup.enabled = true."
  }

  validation {
    condition     = var.backup.transaction_log_retention_days >= 1 && var.backup.transaction_log_retention_days <= 7
    error_message = "transaction_log_retention_days must be between 1 and 7."
  }
}

variable "maintenance_window" {
  description = "Maintenance window. Defaults to Sunday 03:00 UTC on the stable update track."
  type = object({
    day          = optional(number, 7) # 1 = Monday ... 7 = Sunday
    hour         = optional(number, 3) # UTC
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7
    error_message = "maintenance_window.day must be 1-7 (Monday-Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.hour must be 0-23 (UTC)."
  }

  validation {
    condition     = contains(["stable", "canary", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be stable, canary or week5."
  }
}

variable "query_insights" {
  description = "Cloud SQL Query Insights configuration."
  type = object({
    enabled                 = optional(bool, true)
    query_string_length     = optional(number, 1024)
    record_application_tags = optional(bool, true)
    record_client_address   = optional(bool, true)
    query_plans_per_minute  = optional(number, 5)
  })
  default = {}
}

variable "ssl_mode" {
  description = "TLS enforcement for connections. The organizational standard is ENCRYPTED_ONLY; TRUSTED_CLIENT_CERTIFICATE_REQUIRED additionally demands mutual TLS. Do not weaken this without a security review."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ALLOW_UNENCRYPTED_AND_ENCRYPTED", "ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be one of ALLOW_UNENCRYPTED_AND_ENCRYPTED, ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}

variable "encryption_key_name" {
  description = "Optional CMEK (Cloud KMS key resource ID) for the instance. Null uses Google-managed encryption."
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels applied to the instance, e.g. { environment = \"dev\", team = \"payments\" }."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protect the instance from accidental deletion. Disable only for genuinely disposable instances."
  type        = bool
  default     = true
}
