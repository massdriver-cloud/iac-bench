# =========================================================================
# Decisions that belong to the DBA team, instance by instance.
# These have no defaults: a DBA has to make them consciously.
# =========================================================================

variable "name" {
  description = "Name of the Cloud SQL instance. Unique within the project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "The name must start with a lowercase letter and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Environment the instance serves (dev, staging, prod, ...). Recorded as the 'environment' label so cost and access audits can group instances by environment."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.environment))
    error_message = "The environment must contain only lowercase letters, digits and hyphens."
  }
}

variable "region" {
  description = "Region the instance lives in, for example us-central1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+(-[a-z0-9]+)+$", var.region))
    error_message = "The region must look like 'us-central1'."
  }
}

variable "network" {
  description = "The VPC network the instance is reachable from: either its name (apps-dev, expanded against var.project) or a self link (projects/<project>/global/networks/apps-dev, used verbatim). The network team must already have established private services access on this network."
  type        = string

  validation {
    condition = anytrue([
      # Bare network name, resolved against var.project.
      can(regex("^[a-z][a-z0-9-]{0,62}$", var.network)),
      # Project-relative or absolute self link, used as given.
      can(regex("^(https://www\\.googleapis\\.com/compute/(v1|beta)/)?projects/[a-z0-9-]+/global/networks/[a-z][a-z0-9-]{0,62}$", var.network)),
    ])
    error_message = "The network must be a network name ('apps-dev') or a VPC self link ('projects/<project>/global/networks/apps-dev')."
  }
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL version, for example POSTGRES_16. Major version upgrades are a DBA decision, so this is never defaulted."
  type        = string

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+(\\.[0-9]+)?$", var.database_version))
    error_message = "The database_version must be a Cloud SQL PostgreSQL version such as POSTGRES_16."
  }
}

variable "tier" {
  description = "Cloud SQL machine type, for example db-custom-2-8192 (2 vCPU, 8192 MiB RAM). Custom tiers are db-custom-<vCPUs>-<memory MiB>."
  type        = string

  validation {
    condition     = can(regex("^db-[a-z][a-z0-9-]*$", var.tier))
    error_message = "The tier must be a Cloud SQL machine type such as db-custom-2-8192."
  }
}

# =========================================================================
# Decisions a DBA may want to change, with the standard we default to.
# =========================================================================

variable "zone" {
  description = "Preferred zone, for example us-central1-a. Must be inside var.region. Omit (null) to let Cloud SQL pick a zone. For REGIONAL instances this pins the primary zone and the standby is placed in another zone."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "The zone must look like 'us-central1-a'."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS. ENTERPRISE_PLUS does not accept custom database_flags."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "The edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "REGIONAL keeps a synchronous standby in a second zone with automatic failover. ZONAL is a single-zone instance."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "The availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial storage in GiB. Storage auto-resize is always on, so this is a floor, not a ceiling."
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be a whole number between 10 and 65536."
  }
}

variable "disk_type" {
  description = "Persistent disk type: PD_SSD, PD_BALANCED or PD_HDD."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_BALANCED", "PD_HDD"], var.disk_type)
    error_message = "The disk_type must be PD_SSD, PD_BALANCED or PD_HDD."
  }
}

variable "disk_autoresize_limit" {
  description = "Upper bound in GiB for automatic storage growth. 0 means no limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit >= 0 && floor(var.disk_autoresize_limit) == var.disk_autoresize_limit
    error_message = "disk_autoresize_limit must be 0 (no limit) or a whole number of GiB."
  }
}

variable "deletion_protection" {
  description = "Cloud SQL-level deletion protection. Deleting the instance then requires an explicit, two-step opt-out, which is the point."
  type        = bool
  default     = true
}

variable "require_ssl" {
  description = "Reject client connections that are not TLS encrypted. Leave on unless there is a documented reason not to."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Daily automated backup window start, HH:MM in the instance's time zone."
  type        = string
  default     = "04:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM, for example '04:00'."
  }
}

variable "backup_retention_days" {
  description = "How many days of automated backups to keep."
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365 && floor(var.backup_retention_days) == var.backup_retention_days
    error_message = "backup_retention_days must be a whole number between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of write-ahead logs retained for point-in-time recovery. This caps the PITR window (backups alone do not restore to a point in time)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7 && floor(var.transaction_log_retention_days) == var.transaction_log_retention_days
    error_message = "transaction_log_retention_days must be a whole number between 1 and 7."
  }
}

variable "maintenance_window" {
  description = "Weekly Cloud SQL maintenance window: day (1 = Monday .. 7 = Sunday), hour (0-23) and update track (stable, week5, week2, week1, canary)."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string, "stable")
  })
  default = {
    day          = 7
    hour         = 7
    update_track = "stable"
  }

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7
    error_message = "maintenance_window.day must be 1 (Monday) to 7 (Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.hour must be 0-23."
  }

  validation {
    condition     = contains(["stable", "week5", "week2", "week1", "canary"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be one of stable, week5, week2, week1, canary."
  }
}

variable "query_string_length" {
  description = "Bytes of query text Query Insights records per statement (256-4500)."
  type        = number
  default     = 1024

  validation {
    condition     = var.query_string_length >= 256 && var.query_string_length <= 4500 && floor(var.query_string_length) == var.query_string_length
    error_message = "query_string_length must be a whole number between 256 and 4500."
  }
}

variable "record_client_address" {
  description = "Record the client IP and port in Query Insights, which makes per-identity access auditing in the database far more useful."
  type        = bool
  default     = true
}

variable "allocated_ip_range" {
  description = "Name of an allocated IP range (created by the network team) that the private IP should be taken from. null uses the range backing the network's private services access."
  type        = string
  default     = null

  validation {
    condition     = var.allocated_ip_range == null || can(regex("^[a-z][a-z0-9-]{0,62}$", var.allocated_ip_range))
    error_message = "allocated_ip_range must be the name of an allocated range, for example 'cloud-sql-range'."
  }
}

variable "databases" {
  description = "Databases to create on the instance, created with the default template, encoding and locale. Anything more exotic than a name is a psql job."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for db in var.databases : can(regex("^[a-z_][a-z0-9_]{0,62}$", db))])
    error_message = "Database names must be lower-case, start with a letter or underscore, and use only letters, digits and underscores."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL server parameters, name to value, e.g. { max_connections = \"200\" }. IAM database authentication is always on and is not overridable here."
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "IAM database authentication is a module standard and is always on; remove 'cloudsql.iam_authentication' from database_flags."
  }
}

variable "iam_users" {
  description = "Google identities that may log in to the database, keyed by their email address. Values take a type: CLOUD_IAM_USER for people, CLOUD_IAM_SERVICE_ACCOUNT for workload identities. These identities log in with an IAM-generated token, never a password, and they must also hold roles/cloudsql.instanceUser."
  type = map(object({
    type = optional(string, "CLOUD_IAM_USER")
  }))
  default = {}

  validation {
    condition = alltrue([
      for email, user in var.iam_users : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], user.type)
    ])
    error_message = "iam_users[*].type must be CLOUD_IAM_USER (a person) or CLOUD_IAM_SERVICE_ACCOUNT (a service account)."
  }

  validation {
    condition = alltrue([
      for email in keys(var.iam_users) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email))
    ])
    error_message = "Each iam_users key must be the Google identity's email address, e.g. 'alice@example.com' or 'orders@my-project.iam.gserviceaccount.com'."
  }
}

variable "labels" {
  description = "Additional labels for the instance. Merged over the module's standard labels (environment, managed_by), which always win."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.labels :
      can(regex("^[a-z0-9_-]{1,63}$", key)) && can(regex("^[a-z0-9_-]{1,63}$", value))
    ])
    error_message = "Label keys and values must be 1-63 characters of lower-case letters, digits, hyphens and underscores."
  }
}
