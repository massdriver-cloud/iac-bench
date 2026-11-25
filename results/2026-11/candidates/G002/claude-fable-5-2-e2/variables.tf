###############################################################################
# Required: what the instance is, and where it lives
###############################################################################

variable "name" {
  description = "Short name of the database (usually the owning service, e.g. \"orders\"). The instance is named \"<name>-<environment>\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.name))
    error_message = "name must be 1-40 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment the instance serves. Selects the application VPC the instance is attached to (apps-dev, apps-staging or apps-prod) and the environment-dependent defaults (availability, maintenance track)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Region of the primary instance, e.g. \"europe-west1\". Put it where the connecting workloads run."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+(-[a-z]+)+[0-9]+$", var.region))
    error_message = "region must be a Google Cloud region name such as \"us-central1\" or \"europe-west1\"."
  }
}

###############################################################################
# Placement
###############################################################################

variable "project_id" {
  description = "Project that hosts the instance. Null uses the project configured for the provider in the environment."
  type        = string
  default     = null
}

variable "network_project_id" {
  description = "Project that owns the apps-<environment> VPC (the Shared VPC host project). Null means the VPC lives in the instance's own project."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of the private-services-access allocated range to place the instance in. Null lets Cloud SQL pick from the ranges the network team has allocated on the VPC."
  type        = string
  default     = null
}

variable "zone" {
  description = "Preferred zone for the primary (e.g. \"europe-west1-b\"). Null lets Cloud SQL choose."
  type        = string
  default     = null
}

###############################################################################
# Engine and sizing - DBA decisions
###############################################################################

variable "database_version" {
  description = "PostgreSQL major version, in Cloud SQL notation (e.g. \"POSTGRES_17\"). Major versions can be upgraded in place but never downgraded."
  type        = string
  default     = "POSTGRES_17"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a PostgreSQL version such as \"POSTGRES_16\" or \"POSTGRES_17\". This module only manages PostgreSQL."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS. ENTERPRISE_PLUS requires a db-perf-optimized-N-* tier."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine type. ENTERPRISE: db-custom-<vCPU>-<memory MB>. ENTERPRISE_PLUS: db-perf-optimized-N-<vCPU>. The default is a deliberately small 2 vCPU / 7.5 GB machine; size real workloads explicitly."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "REGIONAL (HA, synchronous standby in a second zone) or ZONAL. Null applies the standard: REGIONAL in prod, ZONAL in dev and staging."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null ? true : contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL, ZONAL or null."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD size in GB. Storage auto-grow is always on, so this is only the starting size: later growth (automatic or manual) is not reverted, and changing this value after creation has no effect."
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
    error_message = "disk_autoresize_limit_gb must be 0 (no limit) or a positive whole number."
  }
}

variable "database_flags" {
  description = "PostgreSQL / Cloud SQL flags for tuning (max_connections, work_mem, ...). The module's logging defaults (see locals) can be overridden here; the flags that back the access-audit standard cannot be set."
  type        = map(string)
  default     = {}

  validation {
    condition = length(setintersection(keys(var.database_flags), [
      "cloudsql.iam_authentication",
      "cloudsql.enable_pgaudit",
      "log_connections",
      "log_disconnections",
    ])) == 0
    error_message = "cloudsql.iam_authentication, cloudsql.enable_pgaudit, log_connections and log_disconnections are fixed by this module and cannot be set through database_flags."
  }
}

variable "read_replicas" {
  description = "Read replicas keyed by a short suffix; each is named \"<name>-<environment>-replica-<key>\". Replicas inherit version, edition, flags, network and TLS settings from the primary. region defaults to the primary's region, tier to the primary's tier. encryption_key_name is only needed for a cross-region replica of a CMEK-encrypted primary."
  type = map(object({
    region              = optional(string)
    zone                = optional(string)
    tier                = optional(string)
    encryption_key_name = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.read_replicas) : can(regex("^[a-z0-9]{1,10}$", k))])
    error_message = "read_replicas keys must be 1-10 lowercase letters or digits."
  }
}

###############################################################################
# Contents and access
###############################################################################

variable "databases" {
  description = "Databases to create, keyed by name. Removing an entry stops managing the database but does NOT drop it - dropping data is a deliberate DBA action in SQL."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.databases) : can(regex("^[a-z_][a-z0-9_]{0,62}$", k)) && k != "postgres"])
    error_message = "Database names must be valid unquoted PostgreSQL identifiers (lowercase letters, digits, underscores; max 63 chars) and must not be \"postgres\", which always exists."
  }
}

variable "iam_members" {
  description = <<-EOT
    Google identities allowed to log in to the instance, as IAM members:
    "user:alice@example.com", "group:dba-team@example.com" or
    "serviceAccount:orders@my-project.iam.gserviceaccount.com".
    Each gets an IAM-authenticated database user plus the IAM roles needed to
    connect and log in to this instance only. They start with no privileges on
    any database object; GRANTs are managed by the DBAs in SQL.
  EOT
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for m in var.iam_members :
      can(regex("^(user|group):[a-z0-9._%+'-]+@[a-z0-9.-]+$", m)) ||
      can(regex("^serviceAccount:[a-z0-9.-]+@[a-z0-9.-]+\\.gserviceaccount\\.com$", m))
    ])
    error_message = "Each entry must be \"user:<email>\", \"group:<email>\" or \"serviceAccount:<email ending in .gserviceaccount.com>\", with the email in lowercase."
  }
}

variable "ssl_mode" {
  description = "TLS enforcement. ENCRYPTED_ONLY rejects all non-TLS connections. TRUSTED_CLIENT_CERTIFICATE_REQUIRED additionally requires a client certificate (satisfied automatically by the Cloud SQL Auth Proxy and language connectors). Unencrypted connections cannot be allowed."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}

variable "require_cloud_sql_connectors" {
  description = "Reject every connection that does not come through the Cloud SQL Auth Proxy or a Cloud SQL language connector. Leave false while clients still connect straight to the private IP."
  type        = bool
  default     = false
}

variable "encryption_key_name" {
  description = "Cloud KMS key (projects/.../locations/<region>/keyRings/.../cryptoKeys/...) for customer-managed encryption. Null uses Google-managed encryption. The key must be in the instance's region and the project's Cloud SQL service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on it. Cannot be changed after creation."
  type        = string
  default     = null

  validation {
    condition     = var.encryption_key_name == null ? true : can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.encryption_key_name))
    error_message = "encryption_key_name must look like projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

###############################################################################
# Operations
###############################################################################

variable "backup" {
  description = "Backup schedule and retention. Daily backups and point-in-time recovery are always on; only the schedule, retention and location are adjustable. start_time is HH:MM in UTC. transaction_log_retention_days is the point-in-time-recovery window (max 7 on ENTERPRISE, 35 on ENTERPRISE_PLUS). location null keeps backups in the default multi-region for the instance's region."
  type = object({
    start_time                     = optional(string, "02:00")
    retained_backups               = optional(number, 14)
    transaction_log_retention_days = optional(number, 7)
    location                       = optional(string)
  })
  default = {}

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup.start_time))
    error_message = "backup.start_time must be HH:MM in 24-hour UTC, e.g. \"02:00\"."
  }

  validation {
    condition     = var.backup.retained_backups >= 7 && var.backup.retained_backups <= 365
    error_message = "backup.retained_backups must be between 7 and 365."
  }

  validation {
    condition     = var.backup.transaction_log_retention_days >= 1 && var.backup.transaction_log_retention_days <= 35 && var.backup.transaction_log_retention_days <= var.backup.retained_backups
    error_message = "backup.transaction_log_retention_days must be between 1 and 35 and no larger than backup.retained_backups."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance window in UTC: day 1 (Monday) to 7 (Sunday), hour 0-23. update_track null applies the standard: prod on \"stable\", dev and staging on \"canary\" so they receive each update at least a week before prod."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 4)
    update_track = optional(string)
  })
  default = {}

  validation {
    condition     = contains([1, 2, 3, 4, 5, 6, 7], var.maintenance_window.day) && var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour
    error_message = "maintenance_window.day must be 1-7 (Monday-Sunday) and maintenance_window.hour 0-23."
  }

  validation {
    condition     = var.maintenance_window.update_track == null ? true : contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be canary, stable, week5 or null."
  }
}

variable "deletion_protection" {
  description = "Blocks deletion of the instance and its replicas, both in OpenTofu and in the Cloud SQL API. To decommission, set this to false and apply, then destroy."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Extra labels for the instance (team, cost-centre, ...). The module's own labels (environment, database, managed-by) take precedence."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Label keys and values may only contain lowercase letters, digits, underscores and hyphens (max 63 chars); keys must start with a letter."
  }
}
