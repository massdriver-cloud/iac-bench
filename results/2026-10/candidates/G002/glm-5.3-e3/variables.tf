###############################################################################
# Variables.
#
# The split between required and optional variables is deliberate:
#
#   * The four required inputs are the only per-instance facts the module
#     genuinely cannot know: who/where (project, region), what it is called
#     (name) and which network it serves (network - owned by the network team).
#
#   * Every other input is a DBA decision with a sane default that matches the
#     team's standard. Defaults are production-grade; dev/staging instances
#     dial them down explicitly rather than every instance re-deciding the
#     basics.
#
# Things that must be the same on every instance are not variables at all -
# see locals.tf, instance.tf and README.md.
###############################################################################

###############################################################################
# Required - per-instance facts
###############################################################################

variable "name" {
  type        = string
  description = <<-EOT
    Name of the Cloud SQL instance. Must be unique in the project and follow
    Cloud SQL naming rules (lowercase letter first, then lowercase letters,
    digits and hyphens).
  EOT

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.name))
    error_message = "The instance name must start with a lowercase letter and contain only lowercase letters, digits and hyphens (max 98 characters)."
  }
}

variable "project_id" {
  type        = string
  description = <<-EOT
    Project that owns the instance and everything created alongside it
    (databases, users, the break-glass secret). Cloud SQL requires the VPC
    network passed in `network` to live in this same project.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a Google Cloud project id (6-30 characters, lowercase letters, digits and hyphens)."
  }
}

variable "region" {
  type        = string
  description = "Region for the instance, e.g. us-central1 or europe-west4."

  validation {
    condition     = can(regex("^[a-z]+(-[a-z]+)+[0-9]+$", var.region))
    error_message = "region must look like a Google Cloud region, e.g. us-central1 or europe-west4."
  }
}

variable "network" {
  type        = string
  description = <<-EOT
    VPC network the instance gets its private IP from, as a self-link, e.g.
    "projects/<project>/global/networks/apps-dev" (a bare network name is also
    accepted and resolved inside project_id). Private services access must
    already be configured on this network - that is the network team's
    responsibility, not this module's. The instance has no public IP, so this
    network is the only way in.
  EOT

  validation {
    condition     = can(regex("^(https://www\\.googleapis\\.com/compute/(v1|alpha|beta)/)?projects/[a-z0-9][a-z0-9-]{4,28}[a-z0-9]/global/networks/[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.network)) || can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.network))
    error_message = "network must be a VPC network self-link (projects/PROJECT/global/networks/NAME) or a bare network name."
  }
}

###############################################################################
# Project APIs - the module's own dependencies, nobody else's
###############################################################################

variable "enable_apis" {
  type        = bool
  default     = true
  description = <<-EOT
    Turn on the two APIs this module itself depends on - Cloud SQL Admin
    (sqladmin.googleapis.com) and Secret Manager (secretmanager.googleapis.com)
    - in project_id when they are not already enabled. They are never disabled
    when the module is destroyed. Set to false if project APIs are managed
    centrally by the platform team; the module then assumes both are on.
  EOT
}

###############################################################################
# Capacity, version and availability - genuine per-instance DBA decisions
###############################################################################

variable "tier" {
  type        = string
  default     = "db-custom-2-8192"
  description = <<-EOT
    Machine tier. ENTERPRISE uses "db-custom-<vCPUs>-<MB of RAM>" shapes, e.g.
    db-custom-2-8192 (2 vCPU / 8 GiB). ENTERPRISE_PLUS uses
    "db-perf-optimized-N-XXXX" shapes. Sizing is the DBA's call; the default is
    a general-purpose starting point, not a mandate.
  EOT

  validation {
    condition     = can(regex("^db-[a-z0-9-]+$", var.tier))
    error_message = "tier must be a Cloud SQL machine type, e.g. db-custom-2-8192."
  }
}

variable "edition" {
  type        = string
  default     = "ENTERPRISE"
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS. ENTERPRISE_PLUS requires a db-perf-optimized-* tier."

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "database_version" {
  type        = string
  default     = "POSTGRES_16"
  description = "PostgreSQL major version, e.g. POSTGRES_16. Pick a supported, non-EOL major; this stays a per-instance decision because versions are upgraded deliberately."

  validation {
    condition     = can(regex("^POSTGRES_1[3-9]$", var.database_version))
    error_message = "database_version must be a supported Cloud SQL PostgreSQL version, e.g. POSTGRES_16."
  }
}

variable "availability_type" {
  type        = string
  default     = "REGIONAL"
  description = <<-EOT
    REGIONAL (synchronous HA replica in a second zone) is the standard this
    module defaults to. Choose ZONAL only for disposable instances where HA is
    explicitly not worth the cost. With ZONAL you may pin a preferred `zone`.
  EOT

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "zone" {
  type        = string
  default     = null
  description = "Preferred zone for ZONAL instances, e.g. us-central1-a. May not be set for REGIONAL instances (the API picks the pair of zones)."

  validation {
    condition     = var.zone == null || (var.availability_type == "ZONAL" && can(regex("^[a-z]+(-[a-z]+)+[0-9]-[a-z]$", var.zone)))
    error_message = "zone may only be set for ZONAL instances and must look like us-central1-a."
  }
}

variable "disk_type" {
  type        = string
  default     = "PD_SSD"
  description = "PD_SSD (the standard for database workloads) or PD_HDD for cold/dev data."

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_size" {
  type        = number
  default     = 100
  description = "Initial storage size in GB. Auto-resize grows beyond this when the volume fills."

  validation {
    condition     = var.disk_size >= 10 && var.disk_size <= 65536
    error_message = "disk_size must be between 10 and 65536 GB."
  }
}

variable "disk_autoresize" {
  type        = bool
  default     = true
  description = "Grow storage automatically when it fills. Left on by default - running out of disk is an outage."
}

variable "disk_autoresize_limit" {
  type        = number
  default     = 0
  description = "Upper bound in GB for auto-resize, as a guard against runaway growth. 0 = unlimited. Only meaningful when disk_autoresize is true."

  validation {
    condition     = var.disk_autoresize_limit == 0 || var.disk_autoresize
    error_message = "disk_autoresize_limit can only be set when disk_autoresize is true (0 means unlimited)."
  }
}

###############################################################################
# Databases, flags and users
###############################################################################

variable "databases" {
  type = map(object({
    charset   = optional(string)
    collation = optional(string)
  }))
  default     = {}
  description = <<-EOT
    Databases to create, keyed by database name. Optionally set `charset`
    (PostgreSQL encoding, defaults to UTF8) and `collation` (defaults to
    en_US.UTF-8); both are immutable after creation, so null means "Cloud SQL
    defaults". Removing an entry does NOT drop the database - it is abandoned
    in place; drop it deliberately with SQL when the data is no longer needed.
  EOT

  validation {
    condition     = alltrue([for name, _ in var.databases : can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", name))])
    error_message = "Database names must be valid PostgreSQL identifiers: letters, digits and underscores, starting with a letter or underscore."
  }
}

variable "database_flags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Per-instance database flags for genuine PostgreSQL tuning, e.g.
    { max_connections = "200", shared_buffers = "2GB" }. Values are strings.
    `cloudsql.iam_authentication` is enforced by the module and cannot be set
    here.
  EOT

  validation {
    condition     = alltrue([for name, _ in var.database_flags : lower(name) != "cloudsql.iam_authentication"])
    error_message = "cloudsql.iam_authentication is part of the module's access standard (always on) and cannot be overridden in database_flags."
  }
}

variable "iam_users" {
  type = map(object({
    type = optional(string)
  }))
  default     = {}
  description = <<-EOT
    Google identities that get a database login, keyed by identity email:
    engineers as "dba@company.com", workloads as their service account
    "orders@my-project.iam.gserviceaccount.com". The Cloud SQL user type
    (IAM_USER vs IAM_SERVICE_ACCOUNT) is inferred from the email; set `type`
    explicitly for IAM groups. No passwords are managed anywhere in this
    module - every login maps to an auditable Google identity.
  EOT

  validation {
    condition = alltrue([
      for name, cfg in var.iam_users :
      can(regex("^[^@\\s]+@[^@\\s]+$", name)) && (cfg.type == null || contains(["IAM_USER", "IAM_SERVICE_ACCOUNT", "IAM_GROUP"], cfg.type))
    ])
    error_message = "Each IAM user key must be an email address; type, when set, must be IAM_USER, IAM_SERVICE_ACCOUNT or IAM_GROUP."
  }
}

###############################################################################
# Backups and recovery - standard policy, DBA-tunable parameters
###############################################################################

variable "backups_enabled" {
  type        = bool
  default     = true
  description = "Daily automated backups. On by default; switching this off for an instance is a deliberate, reviewable decision."
}

variable "backup_start_time" {
  type        = string
  default     = "02:00"
  description = "Start of the 4-hour daily backup window, UTC (HH:MM). Stagger this across instances to spread backup I/O."

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a 24h UTC time formatted HH:MM."
  }
}

variable "backup_retention_count" {
  type        = number
  default     = 7
  description = "Number of automated backups to retain (1-365)."

  validation {
    condition     = var.backup_retention_count >= 1 && var.backup_retention_count <= 365
    error_message = "backup_retention_count must be between 1 and 365."
  }
}

variable "point_in_time_recovery_enabled" {
  type        = bool
  default     = true
  description = "Keep write-ahead logs so the instance can be restored to any point in time. Requires backups_enabled."

  validation {
    condition     = !var.point_in_time_recovery_enabled || var.backups_enabled
    error_message = "point_in_time_recovery_enabled requires backups_enabled."
  }
}

variable "transaction_log_retention_days" {
  type        = number
  default     = 7
  description = "Days of write-ahead logs retained for point-in-time recovery (1-30). Together with backup_retention_count this defines the recovery window."

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 30
    error_message = "transaction_log_retention_days must be between 1 and 30."
  }
}

###############################################################################
# Maintenance and observability
###############################################################################

variable "maintenance_window_day" {
  type        = number
  default     = 7
  description = "Day of the weekly maintenance window: 1 = Monday ... 7 = Sunday. Times are UTC. Stagger windows across instances so the fleet is never patched all at once."

  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "maintenance_window_day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_window_hour" {
  type        = number
  default     = 6
  description = "Hour (UTC) at which the one-hour weekly maintenance window starts."

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "maintenance_window_hour must be between 0 and 23."
  }
}

variable "maintenance_update_track" {
  type        = string
  default     = "stable"
  description = "Maintenance update track: stable (default) or canary. Use canary deliberately on one instance to catch problems early."

  validation {
    condition     = contains(["stable", "canary"], var.maintenance_update_track)
    error_message = "maintenance_update_track must be stable or canary."
  }
}

variable "query_insights_enabled" {
  type        = bool
  default     = true
  description = "Cloud SQL Insights: query-level latency and load metrics. On by default - when a database is slow, this is the first place to look."
}

###############################################################################
# Security and lifecycle
###############################################################################

variable "disk_encryption_key" {
  type        = string
  default     = null
  description = <<-EOT
    Full resource name of a Cloud KMS crypto key for customer-managed
    encryption (projects/.../locations/.../keyRings/.../cryptoKeys/...), or
    null for Google-managed encryption. The security team must grant the
    Cloud SQL service agent roles/cloudkms.cryptoKeyEncrypterDecrypter on the
    key before the instance is created - key grants are not this module's to
    make.
  EOT

  validation {
    condition     = var.disk_encryption_key == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.disk_encryption_key))
    error_message = "disk_encryption_key must be a full Cloud KMS crypto key resource name, or null for Google-managed keys."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = <<-EOT
    Refuses to destroy the instance unless this is first flipped to false and
    applied. On by default: instances hold data and deletion is irreversible.
    Decommissioning is a two-step, deliberate act.
  EOT
}

variable "manage_postgres_password" {
  type        = bool
  default     = true
  description = <<-EOT
    Generate a strong random password for the built-in `postgres` superuser
    and store it in Secret Manager. The superuser exists on every Cloud SQL
    PostgreSQL instance; giving it a generated, access-controlled password is
    the break-glass path for one-time work such as granting cloudsqlsuperuser
    to the first IAM logins. Set false to leave the password unset (pure
    IAM-only until someone sets one with gcloud).
  EOT
}

variable "postgres_password_readers" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Principals granted roles/secretmanager.secretAccessor on the generated
    postgres password secret, e.g. ["group:dba-team@company.com"]. Leave empty
    to manage access with your own IAM tooling instead.
  EOT

  validation {
    condition     = alltrue([for m in var.postgres_password_readers : can(regex("^(user|group|serviceAccount|domain):.+$", m))])
    error_message = "Each reader must be an IAM member of the form user:..., group:..., serviceAccount:... or domain:...."
  }
}

variable "allocated_ip_range" {
  type        = string
  default     = null
  description = "Name of an allocated IP range in the VPC (created and owned by the network team) from which the instance's private IP is carved. null = any range available through private services access."

  validation {
    condition     = var.allocated_ip_range == null || can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.allocated_ip_range))
    error_message = "allocated_ip_range must be an IP range name, or null."
  }
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Additional labels on the instance and its secret (cost centre, application, environment, ...). `managed_by` and `module` are reserved."

  validation {
    condition     = alltrue([for k, _ in var.labels : !contains(["managed_by", "module"], k)])
    error_message = "The labels `managed_by` and `module` are set by the module and cannot be overridden."
  }

  validation {
    condition = alltrue(concat(
      [for k, _ in var.labels : can(regex("^[a-z0-9_-]{1,63}$", k))],
      [for _, v in var.labels : can(regex("^[a-z0-9_-]{0,63}$", v))],
    ))
    error_message = "Labels must be 1-63 characters of lowercase letters, digits, underscores and hyphens (values may be empty)."
  }
}
