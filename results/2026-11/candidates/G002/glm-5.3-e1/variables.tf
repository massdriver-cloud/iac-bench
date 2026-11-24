# -----------------------------------------------------------------------------
# Required decisions - genuinely per-instance DBA decisions
# -----------------------------------------------------------------------------

variable "project" {
  description = "Google Cloud project that owns the instance and the environment VPC network. This is the same project the Google provider is configured for."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.project))
    error_message = "project must be a Google Cloud project id, e.g. apps-prod-42."
  }
}

variable "name" {
  description = "Cloud SQL instance name. Must start with a lowercase letter and contain only lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}$", var.name))
    error_message = "The instance name must start with a lowercase letter and contain only lowercase letters, digits and hyphens (at most 97 characters)."
  }
}

variable "region" {
  description = "Google Cloud region the instance lives in, e.g. europe-west4. Read replicas may use a different region via read_replicas."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+(-[a-z0-9]+)+$", var.region))
    error_message = "region must be a Google Cloud region name such as us-central1 or europe-west4."
  }
}

variable "tier" {
  description = <<-DESC
    Machine tier of the instance, e.g. "db-custom-4-15360" (4 vCPU / 15 GB) for
    a normal sized database, or a shared-core tier such as "db-g1-small" for
    throwaway development instances.
  DESC
  type        = string

  validation {
    condition     = can(regex("^db-", var.tier))
    error_message = "tier must be a Cloud SQL machine tier such as db-custom-4-15360 or db-g1-small."
  }
}

variable "network" {
  description = <<-DESC
    VPC network the instance is reachable on: either the network name (resolved
    in the project) or the network's full self link
    (projects/<project>/global/networks/<name>). Private services access must
    already be configured on this network - the network team owns that side
    and has already done it for apps-dev, apps-staging and apps-prod.
  DESC
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.network)) || can(regex("^(https?://|projects/)", var.network))
    error_message = "network must be either a VPC network name or a VPC self link (projects/<project>/global/networks/<name> or a https URL)."
  }
}

# -----------------------------------------------------------------------------
# Standard decisions - the module ships the fleet default; the DBA team can
# still override any of these when an instance genuinely needs to differ.
# -----------------------------------------------------------------------------

variable "database_version" {
  description = "PostgreSQL major version. Bump the default deliberately and fleet-wide; per-instance overrides will fragment the fleet."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "database_version must be one of POSTGRES_13, POSTGRES_14, POSTGRES_15, POSTGRES_16 or POSTGRES_17."
  }
}

variable "edition" {
  description = "Cloud SQL edition. ENTERPRISE is the fleet default; ENTERPRISE_PLUS only on instances that need it and are in a supported region."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "ZONAL or REGIONAL. REGIONAL (regional high availability with automatic failover) is the default; only use ZONAL for disposable instances."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "deletion_protection" {
  description = "While enabled, terraform destroy refuses to delete the instance. Only disable for throwaway instances, and know what you are doing."
  type        = bool
  default     = true
}

variable "disk_size_gb" {
  description = "Initial SSD size in GB. Auto-resize is on, so this is just the starting point."
  type        = number
  default     = 10

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10 GB."
  }
}

variable "disk_autoresize" {
  description = "Let Cloud SQL grow the disk automatically when it fills up. Availability first: the default is on."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "Ceiling in GB for auto-resize, 0 meaning no limit. Set a ceiling when you want a hard cost guardrail instead of the availability-first default."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit >= 0
    error_message = "disk_autoresize_limit must be 0 (no limit) or a positive number of GB."
  }
}

variable "allocated_ip_range" {
  description = "Name of the allocated range the network team reserved in the VPC for Cloud SQL private IPs, if they carved out a specific one. Leave null to let private services access pick the range."
  type        = string
  default     = null
}

variable "kms_key_name" {
  description = "Full self link of the Cloud KMS key to encrypt the instance's data with (CMEK). Leave null for the Google-managed key. The instance's service account (see the instance_service_account_email output) needs roles/cloudkms.cryptoKeyEncrypterDecrypter on the key, and the key must be in the instance's region."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Recovery posture
# -----------------------------------------------------------------------------

variable "point_in_time_recovery_enabled" {
  description = "Keep transaction logs so the database can be restored to any point in time. On by default; disable only for instances you are happy to lose."
  type        = bool
  default     = true
}

variable "backup_retention_count" {
  description = "How many daily automated backups to retain. 7 is the fleet default; raise it where compliance requires longer retention."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_count >= 1 && var.backup_retention_count <= 365
    error_message = "backup_retention_count must be between 1 and 365."
  }
}

variable "backup_start_time" {
  description = "UTC start of the daily automated backup window, in HH:MM."
  type        = string
  default     = "06:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a HH:MM UTC time, e.g. 06:00."
  }
}

variable "maintenance_window" {
  description = "When Cloud SQL may apply patches to the instance. All times are UTC. update_track is 'stable' (rolled out gradually) or 'canary' (early)."
  type = object({
    day          = string
    hour         = number
    update_track = string
  })
  default = {
    day          = "SUNDAY"
    hour         = 3
    update_track = "stable"
  }

  validation {
    condition     = contains(["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"], var.maintenance_window.day)
    error_message = "maintenance_window.day must be an uppercase day name, e.g. SUNDAY."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.hour must be between 0 and 23 (UTC)."
  }

  validation {
    condition     = contains(["stable", "canary"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be 'stable' or 'canary'."
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL specifics
# -----------------------------------------------------------------------------

variable "database_flags" {
  description = <<-DESC
    PostgreSQL server parameters to set on the instance, as a map of flag name
    to value (values as strings, e.g. { max_connections = "200" }). Every flag
    a DBA sets here is theirs; the module only pins cloudsql.iam_authentication,
    which cannot be overridden.
  DESC
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "The module always sets cloudsql.iam_authentication=on; it cannot be overridden via database_flags."
  }
}

variable "databases" {
  description = "Databases to create on the instance, keyed by database name. charset and collation are optional and default to the instance defaults (UTF8 / en_US.UTF8)."
  type = map(object({
    charset   = optional(string)
    collation = optional(string)
  }))
  default = {}
}

variable "read_replicas" {
  description = <<-DESC
    Read replicas, keyed by the replica's instance name (which must differ from
    the primary's). Each replica defaults to the primary's tier, disk, region
    and availability type; override per replica as needed. Replicas inherit the
    primary's PostgreSQL flags.
  DESC
  type = map(object({
    tier              = optional(string)
    region            = optional(string)
    availability_type = optional(string)
    disk_size_gb      = optional(number)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Access - Google identities only
# -----------------------------------------------------------------------------

variable "iam_database_users" {
  description = "Google accounts (engineers) that get IAM database logins. Each receives roles/cloudsql.instanceUser and roles/cloudsql.client at project level and logs in with their email as the database username."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.iam_database_users : can(regex("^[^@]+@[^@]+$", email))])
    error_message = "iam_database_users must be a list of Google account email addresses."
  }
}

variable "iam_database_groups" {
  description = "Google groups that get IAM database logins. Members authenticate with their own account; the group is the thing granted access."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.iam_database_groups : can(regex("^[^@]+@[^@]+$", email))])
    error_message = "iam_database_groups must be a list of Google group email addresses."
  }
}

variable "iam_service_accounts" {
  description = "Service accounts of the workloads (GKE workloads, Compute Engine VMs) that connect to the database. Each receives roles/cloudsql.instanceUser and roles/cloudsql.client at project level."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.iam_service_accounts : can(regex("^[^@]+@[^@]+$", email))])
    error_message = "iam_service_accounts must be a list of service account email addresses."
  }
}

variable "labels" {
  description = "Labels applied to the instance, e.g. { environment = \"apps-prod\", cost-center = \"dba\" }."
  type        = map(string)
  default     = {}
}
