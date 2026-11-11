# ---------------------------------------------------------------------------
# Required: identity and placement of the instance
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Project that will own the Cloud SQL instance."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID."
  }
}

variable "name" {
  description = "Short name of the database service (for example \"orders\"). The instance is named <name>-<environment>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,48}[a-z0-9]$", var.name))
    error_message = "name must be 2-50 characters, lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment the instance serves. Selects the VPC network (apps-<environment>) and the environment-specific defaults (HA, backup retention, maintenance track)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Region for the instance. Should match the region of the workloads that connect to it."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a Google Cloud region such as europe-west1."
  }
}

variable "database_version" {
  description = "PostgreSQL major version, in Cloud SQL notation (for example POSTGRES_16). Deliberately has no default: it cannot be downgraded, so it is always an explicit choice."
  type        = string

  validation {
    condition     = can(regex("^POSTGRES_[1-9][0-9]$", var.database_version))
    error_message = "database_version must be a PostgreSQL version such as POSTGRES_16. This module only manages PostgreSQL."
  }
}

# ---------------------------------------------------------------------------
# Network (owned by the network team; this module only attaches to it)
# ---------------------------------------------------------------------------

variable "network_project_id" {
  description = "Project that hosts the apps-<environment> VPC network, if it is a Shared VPC host project different from project_id. Defaults to project_id."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of the private services access allocated range to place the instance in. Leave null to let Cloud SQL pick from the ranges the network team has allocated."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Sizing (DBA decisions)
# ---------------------------------------------------------------------------

variable "edition" {
  description = "Cloud SQL edition. Set explicitly so the API default (which differs by PostgreSQL version) never decides it."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine type. ENTERPRISE uses db-custom-<vCPU>-<memory MB>; ENTERPRISE_PLUS uses the db-perf-optimized-N-* family."
  type        = string
  default     = "db-custom-2-8192"

  validation {
    condition     = can(regex("^db-[a-z0-9-]+$", var.tier))
    error_message = "tier must be a Cloud SQL machine type such as db-custom-2-8192."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD size in GB. Storage auto-grows from here, so later changes to this value are ignored (see disk_autoresize_limit_gb)."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be a whole number of at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Ceiling for automatic storage growth in GB. 0 means no ceiling."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0 && floor(var.disk_autoresize_limit_gb) == var.disk_autoresize_limit_gb
    error_message = "disk_autoresize_limit_gb must be a whole number, 0 or greater."
  }
}

variable "high_availability" {
  description = "Run a regional (HA) instance with a standby in a second zone. Null means the environment default: on for prod, off for dev and staging."
  type        = bool
  default     = null
}

variable "zone" {
  description = "Preferred zone for the primary, to co-locate with the application. Null lets Cloud SQL choose."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# PostgreSQL configuration (DBA decisions)
# ---------------------------------------------------------------------------

variable "databases" {
  description = "Names of the databases to create on the instance. Removing a name stops managing the database but does not drop it."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.databases : can(regex("^[a-z_][a-z0-9_]{0,62}$", d))])
    error_message = "Database names must be lowercase letters, digits and underscores, start with a letter or underscore, and be at most 63 characters."
  }

  validation {
    condition     = !contains(var.databases, "postgres")
    error_message = "The postgres database always exists and is not managed by this module."
  }
}

variable "database_flags" {
  description = "PostgreSQL flags (parameter name => value) for tuning. Merged over the module's logging defaults. The access-control and audit flags the module enforces cannot be set here."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Access: Google identities only
# ---------------------------------------------------------------------------

variable "iam_groups" {
  description = "Google group emails whose members may log in with IAM database authentication. Preferred over listing individuals."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.iam_groups : can(regex("^[a-z0-9._+-]+@[a-z0-9.-]+$", e))])
    error_message = "iam_groups must be lowercase group email addresses."
  }
}

variable "iam_users" {
  description = "Email addresses of individual engineers who may log in with IAM database authentication."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.iam_users : can(regex("^[a-z0-9._+-]+@[a-z0-9.-]+$", e)) && !endswith(e, ".gserviceaccount.com")])
    error_message = "iam_users must be lowercase user email addresses. Service accounts belong in iam_service_accounts."
  }
}

variable "iam_service_accounts" {
  description = "Service account emails of the workloads (GKE via Workload Identity, Compute Engine) that may log in with IAM database authentication."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.iam_service_accounts : can(regex("^[a-z0-9-]+@[a-z0-9.-]+\\.gserviceaccount\\.com$", e))])
    error_message = "iam_service_accounts must be full service account emails ending in .gserviceaccount.com."
  }
}

# ---------------------------------------------------------------------------
# Backups and maintenance (DBA decisions; backups themselves are always on)
# ---------------------------------------------------------------------------

variable "backup_start_time" {
  description = "Start of the daily backup window, HH:MM in UTC."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in 24-hour UTC, for example 02:00."
  }
}

variable "backup_retention_count" {
  description = "Number of daily backups to keep. Null means the environment default: 30 for prod, 7 for dev and staging."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_count == null ? true : (var.backup_retention_count >= 7 && var.backup_retention_count <= 365 && floor(var.backup_retention_count) == var.backup_retention_count)
    error_message = "backup_retention_count must be a whole number between 7 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of write-ahead log kept for point-in-time recovery. ENTERPRISE allows 1-7, ENTERPRISE_PLUS allows 1-35."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35 && floor(var.transaction_log_retention_days) == var.transaction_log_retention_days
    error_message = "transaction_log_retention_days must be a whole number between 1 and 35."
  }
}

variable "backup_location" {
  description = "Location for backups (a region or multi-region such as eu). Null uses the Cloud SQL default multi-region closest to the instance."
  type        = string
  default     = null
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC. day is 1 (Monday) to 7 (Sunday), hour is 0-23."
  type = object({
    day  = number
    hour = number
  })
  default = {
    day  = 7
    hour = 4
  }

  validation {
    condition     = contains([1, 2, 3, 4, 5, 6, 7], var.maintenance_window.day) && contains(range(0, 24), var.maintenance_window.hour)
    error_message = "maintenance_window.day must be 1-7 (Monday-Sunday) and maintenance_window.hour must be 0-23."
  }
}

# ---------------------------------------------------------------------------
# Protection and metadata
# ---------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Block deletion of the instance, both in OpenTofu and in the Cloud SQL API. Set to false and apply before a deliberate teardown."
  type        = bool
  default     = true
}

variable "kms_key_name" {
  description = "Customer-managed Cloud KMS key (full resource ID, same region as the instance) for encryption at rest. Null uses Google-managed encryption. Cannot be changed after creation."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null ? true : can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must look like projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

variable "labels" {
  description = "Extra labels for the instance (for example team or cost-centre). The module's own labels take precedence."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Label keys and values must be lowercase letters, digits, underscores and hyphens, at most 63 characters; keys must start with a letter."
  }
}
