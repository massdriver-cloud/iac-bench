###############################################################################
# Required: the decisions that belong to the DBA for each instance.
#
# These deliberately have no default. Engine major version and machine size
# are per-instance decisions, and a module-level default that changed later
# would trigger a major-version upgrade or a resize on every instance that
# relied on it.
###############################################################################

variable "project_id" {
  description = "Project the Cloud SQL instance is created in."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (not a project number or display name)."
  }
}

variable "name" {
  description = "Instance name. Used as-is, with no generated suffix, so it is predictable in connection strings. Cloud SQL does not allow a deleted instance's name to be reused for about a week."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter, contain only lowercase letters, digits and hyphens, not end with a hyphen, and be at most 63 characters."
  }
}

variable "environment" {
  description = "Environment the instance serves. Selects the VPC network (apps-<environment>) and the environment-dependent defaults for availability, backup retention and maintenance track."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Region for the instance, e.g. europe-west1. Should be the region the connecting workloads run in."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a region name such as europe-west1 or us-central1 (not a zone)."
  }
}

variable "database_version" {
  description = "PostgreSQL major version. Changing it on an existing instance performs an in-place major version upgrade."
  type        = string

  validation {
    condition     = contains(["POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "database_version must be one of POSTGRES_14, POSTGRES_15, POSTGRES_16, POSTGRES_17 (the versions this module's flag baseline has been written for)."
  }
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-4-16384 (Enterprise) or db-perf-optimized-N-8 (Enterprise Plus). Shared-core tiers are rejected for prod."
  type        = string

  validation {
    condition     = can(regex("^db-[a-z0-9-]+$", var.tier))
    error_message = "tier must be a Cloud SQL machine tier such as db-custom-2-7680 or db-perf-optimized-N-4."
  }
}

###############################################################################
# Sizing, edition and availability
###############################################################################

variable "edition" {
  description = "Cloud SQL edition. Always set explicitly by the module, because the API default differs by PostgreSQL version and silently changes which tiers are valid."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "high_availability" {
  description = "Run a regional (multi-zone, automatic failover) instance. Leave null for the standard: regional in prod, zonal in dev and staging."
  type        = bool
  default     = null
}

variable "zone" {
  description = "Preferred zone for the primary, e.g. europe-west1-b. Leave null to let Cloud SQL choose."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "zone must be a zone name such as europe-west1-b."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD size in GB. Storage auto-grow is always on, so this is only the starting size; later growth is not reverted by the module."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be a whole number of at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for storage auto-grow in GB. 0 means no limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0 && floor(var.disk_autoresize_limit_gb) == var.disk_autoresize_limit_gb
    error_message = "disk_autoresize_limit_gb must be a whole number, 0 (unlimited) or greater."
  }
}

###############################################################################
# Networking
#
# The network itself is not an input: it is always apps-<environment>.
###############################################################################

variable "network_project_id" {
  description = "Project that owns the apps-<environment> VPC network, if it is a Shared VPC host project different from project_id. Leave null when the network lives in project_id."
  type        = string
  default     = null

  validation {
    condition     = var.network_project_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.network_project_id))
    error_message = "network_project_id must be a valid Google Cloud project ID."
  }
}

variable "allocated_ip_range" {
  description = "Name of a specific private services access allocated range to place the instance in, if the network team has reserved one for databases. Leave null to use any range on the peering."
  type        = string
  default     = null

  validation {
    condition     = var.allocated_ip_range == null || can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.allocated_ip_range))
    error_message = "allocated_ip_range must be the name of an allocated range (lowercase letters, digits, hyphens), not a CIDR."
  }
}

###############################################################################
# Backups and maintenance
#
# Automated backups and point-in-time recovery are always on. Only the
# schedule and retention are adjustable.
###############################################################################

variable "backup_start_time" {
  description = "Start of the daily four-hour backup window, HH:MM in UTC."
  type        = string
  default     = "01:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in 24-hour UTC, e.g. 01:00."
  }
}

variable "backup_location" {
  description = "Region or multi-region to store backups in, e.g. eu. Leave null for the Cloud SQL default (the multi-region closest to the instance)."
  type        = string
  default     = null
}

variable "backup_retained_count" {
  description = "Number of daily automated backups to keep. Leave null for the standard: 30 in prod, 7 in dev and staging."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retained_count == null ? true : (var.backup_retained_count >= 1 && var.backup_retained_count <= 365 && floor(var.backup_retained_count) == var.backup_retained_count)
    error_message = "backup_retained_count must be a whole number between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of WAL kept for point-in-time recovery. 1-7 on Enterprise, 1-35 on Enterprise Plus."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35 && floor(var.transaction_log_retention_days) == var.transaction_log_retention_days
    error_message = "transaction_log_retention_days must be a whole number between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC. day is 1 (Monday) to 7 (Sunday), hour is 0-23."
  type = object({
    day  = number
    hour = number
  })
  default = {
    day  = 7
    hour = 6
  }

  validation {
    condition     = contains([1, 2, 3, 4, 5, 6, 7], var.maintenance_window.day) && contains(range(24), var.maintenance_window.hour)
    error_message = "maintenance_window.day must be 1-7 (Monday-Sunday) and maintenance_window.hour must be 0-23."
  }
}

variable "deny_maintenance_period" {
  description = "Optional period (at most 90 days) during which Cloud SQL must not perform maintenance, e.g. a change freeze. Dates are YYYY-MM-DD, or MM-DD to recur every year."
  type = object({
    start_date = string
    end_date   = string
    time       = optional(string, "00:00:00")
  })
  default = null

  validation {
    condition = var.deny_maintenance_period == null ? true : (
      can(regex("^([0-9]{4}-)?[0-9]{2}-[0-9]{2}$", var.deny_maintenance_period.start_date)) &&
      can(regex("^([0-9]{4}-)?[0-9]{2}-[0-9]{2}$", var.deny_maintenance_period.end_date)) &&
      can(regex("^[0-9]{2}:[0-9]{2}:[0-9]{2}$", var.deny_maintenance_period.time))
    )
    error_message = "deny_maintenance_period dates must be YYYY-MM-DD or MM-DD, and time must be HH:MM:SS."
  }
}

###############################################################################
# PostgreSQL configuration
###############################################################################

variable "database_flags" {
  description = "PostgreSQL flags to set on the instance (and its read replicas), as name => value. Merged over the module's tuning defaults. The access and audit flags the module enforces (cloudsql.iam_authentication, cloudsql.enable_pgaudit, pgaudit.log, log_connections, log_disconnections) cannot be set here."
  type        = map(string)
  default     = {}
}

variable "pgaudit_extra_classes" {
  description = "pgAudit statement classes to log in addition to the enforced baseline of ddl and role. Adding read or write logs every query and has a real performance and log-volume cost."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.pgaudit_extra_classes : contains(["read", "write", "function", "misc", "misc_set"], c)])
    error_message = "pgaudit_extra_classes may only contain: read, write, function, misc, misc_set (ddl and role are always logged)."
  }
}

variable "databases" {
  description = "Databases to create, as name => settings. Removing an entry stops managing the database but does not drop it; dropping data is left as a deliberate manual action."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}

  validation {
    condition     = alltrue([for n in keys(var.databases) : can(regex("^[a-z_][a-z0-9_$-]{0,62}$", n))])
    error_message = "Database names must start with a lowercase letter or underscore, contain only lowercase letters, digits, underscores, hyphens or $, and be at most 63 characters."
  }

  validation {
    condition     = alltrue([for n in keys(var.databases) : !contains(["postgres", "template0", "template1", "cloudsqladmin"], n)])
    error_message = "postgres, template0, template1 and cloudsqladmin already exist on every instance and cannot be managed here."
  }
}

###############################################################################
# Access
#
# Access is by Google identity only. The module never creates a password
# user and never puts a credential in state.
###############################################################################

variable "iam_members" {
  description = "Google identities allowed to log in to this instance with IAM database authentication, as IAM principals: user:alice@example.com, serviceAccount:app@my-project.iam.gserviceaccount.com or group:dba-team@example.com. Each gets a PostgreSQL role plus instance-scoped Cloud SQL Client and Instance User grants. Privileges inside PostgreSQL are granted by the DBAs in SQL."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.iam_members : can(regex("^(user|serviceAccount|group):[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]+$", m))])
    error_message = "Each iam_members entry must be user:<email>, serviceAccount:<email> or group:<email>, in lowercase."
  }

  validation {
    condition     = alltrue([for m in var.iam_members : endswith(m, ".gserviceaccount.com") if startswith(m, "serviceAccount:")])
    error_message = "serviceAccount: entries must be full service account emails ending in .gserviceaccount.com."
  }

  validation {
    condition     = alltrue([for m in var.iam_members : length(trimsuffix(split(":", m)[1], ".gserviceaccount.com")) <= 63])
    error_message = "PostgreSQL role names are limited to 63 characters: the email (for service accounts, the email without .gserviceaccount.com) must not be longer than that."
  }
}

###############################################################################
# Read replicas
###############################################################################

variable "read_replicas" {
  description = "Read replicas, keyed by a short suffix; each is created as <name>-replica-<key>. tier defaults to the primary's tier and region to the primary's region. They share the primary's network, flags and access rules."
  type = map(object({
    tier         = optional(string)
    region       = optional(string)
    zone         = optional(string)
    kms_key_name = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.read_replicas) : can(regex("^[a-z0-9]([a-z0-9-]{0,14}[a-z0-9])?$", k))])
    error_message = "read_replicas keys must be 1-16 characters of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

###############################################################################
# Encryption, labels, lifecycle
###############################################################################

variable "kms_key_name" {
  description = "Customer-managed encryption key for the instance, as projects/<project>/locations/<region>/keyRings/<ring>/cryptoKeys/<key>. The key must be in the instance's region and the Cloud SQL service agent must already be allowed to use it. Leave null for Google-managed encryption. Cannot be changed after creation."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must look like projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

variable "labels" {
  description = "Extra labels for the instance, e.g. owning team or cost centre. The module adds environment and managed-by itself."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Label keys must start with a lowercase letter; keys and values may contain only lowercase letters, digits, underscores and hyphens, up to 63 characters."
  }

  validation {
    condition     = alltrue([for k in keys(var.labels) : !contains(["environment", "managed-by"], k)])
    error_message = "The environment and managed-by labels are set by the module and cannot be overridden."
  }
}

variable "deletion_protection" {
  description = "Protect the instance and its replicas from deletion, both in OpenTofu and in the Cloud SQL API. To decommission an instance, apply with this set to false first, then destroy."
  type        = bool
  default     = true
}
