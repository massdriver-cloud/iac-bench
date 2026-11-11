###############################################################################
# Placement
###############################################################################

variable "project_id" {
  description = "Project that owns the Cloud SQL instances, their databases, their logins and the IAM bindings this module grants."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id)) &&
      length(var.project_id) >= 6 &&
      length(var.project_id) <= 30
    )
    error_message = "project_id must be a Google Cloud project id: 6-30 characters, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Region for the primary instance. Individual replicas can override this to create cross-region replicas."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must look like a Google Cloud region, for example us-central1 or europe-west4."
  }
}

variable "zone" {
  description = "Zone for the primary instance. Leave unset to let the service choose a zone within the region. Replicas take their own zone."
  type        = string
  default     = null
}

variable "network" {
  description = <<-EOT
    VPC network the instances attach to over private services access: either a
    network name (resolved in the network's project) or a full network self
    link.

    The module is private-IP only: no public IP addresses and no authorized
    networks, ever. The network team must already have configured private
    services access on this network (one per environment: apps-dev,
    apps-staging, apps-prod).
  EOT
  type        = string
}

variable "network_project_id" {
  description = "Project that owns the VPC network. Defaults to project_id. Set it when the network lives in a different project, for example a Shared VPC host project owned by the network team."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of the allocated range, managed by the network team, from which the instances' private IP addresses are reserved. Leave unset unless the network team dedicated a range to Cloud SQL."
  type        = string
  default     = null
}

###############################################################################
# Instance shape - decisions the DBA team makes per instance
###############################################################################

variable "name" {
  description = "Name of the primary instance. Replicas are named <name>-<replica key>."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.name)) && length(var.name) <= 77
    error_message = "The instance name must start with a lowercase letter, contain only lowercase letters, digits and hyphens, and be at most 77 characters (so replica names stay within Cloud SQL's 98 character limit)."
  }
}

variable "database_version" {
  description = "PostgreSQL engine version, for example POSTGRES_16."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a PostgreSQL version such as POSTGRES_16."
  }
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

variable "tier" {
  description = "Machine tier for the primary instance, for example db-custom-4-15360 for 4 vCPU / 15 GiB. Replicas default to this tier and can override it individually."
  type        = string
}

variable "availability_type" {
  description = "ZONAL for a single-zone instance, REGIONAL for a highly available instance with an automatic failover replica."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size" {
  description = "Data disk size in GiB. The disk grows automatically by default; see disk_autoresize."
  type        = number
  default     = 10

  validation {
    condition     = var.disk_size >= 10
    error_message = "Cloud SQL for PostgreSQL requires at least 10 GiB of disk."
  }
}

variable "disk_type" {
  description = "Data disk type: PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_autoresize" {
  description = "Let Cloud SQL grow the data disk automatically when it fills up."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "Maximum disk size in GiB when autoresizing, 0 for no limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit >= 0
    error_message = "disk_autoresize_limit must be 0 (no limit) or a size in GiB."
  }
}

variable "database_flags" {
  description = <<-EOT
    PostgreSQL server flags, name => value (values are always strings), for
    example { "log_min_duration_statement" = "1000" }. Flags that need a
    restart will restart the instance when applied - plan accordingly. Use
    this to enable pgaudit (shared_preload_libraries plus CREATE EXTENSION)
    if the security team asks for statement-level audit logging.
  EOT
  type        = map(string)
  default     = {}
}

variable "user_labels" {
  description = <<-EOT
    Additional labels on the instances, for example
    { "app" = "billing", "env" = "prod" }. The module always adds
    managed-by = opentofu.
  EOT
  type        = map(string)
  default     = {}
}

variable "replicas" {
  description = <<-EOT
    Read replicas of the primary, keyed by a short suffix that is appended to
    the instance name (<name>-<key>) and used as the key in the replicas
    output. All fields are optional: tier, disk_size and disk_type default to
    the primary's, availability_type defaults to ZONAL, and region defaults
    to the primary's region - set it for a cross-region replica (which needs
    private services access in that region too).
  EOT
  type = map(object({
    tier              = optional(string)
    region            = optional(string)
    zone              = optional(string)
    availability_type = optional(string, "ZONAL")
    disk_size         = optional(number)
    disk_type         = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for key in keys(var.replicas) :
      can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", key)) && length(key) <= 20
    ])
    error_message = "Replica keys must start with a lowercase letter, contain only lowercase letters, digits and hyphens, and be at most 20 characters."
  }
}

###############################################################################
# Access control
###############################################################################

variable "iam_users" {
  description = <<-EOT
    Google identities that can sign in to the instance with IAM database
    authentication, keyed by principal email. This is the module's access
    model: no passwords are stored or managed for these logins, and the
    security team can audit database access by Google identity.

    Pass engineers as their user email and workloads (GKE, Compute Engine) as
    their service account email; the module strips the .gserviceaccount.com
    suffix from service accounts because that is the PostgreSQL login name
    Cloud SQL expects (see the iam_login_names output).

    Every principal is granted roles/cloudsql.instanceUser in project_id,
    which is required to log in with IAM database authentication. Set
    grant_cloudsql_client = true to also grant roles/cloudsql.client, which
    is required by the Cloud SQL Auth Proxy and the language connectors.
    Note that cloudsql.client is project-scoped: it allows connecting to
    every Cloud SQL instance in the project.
  EOT
  type = map(object({
    grant_cloudsql_client = optional(bool, false)
  }))
  default = {}

  validation {
    condition = alltrue([
      for email in keys(var.iam_users) : can(regex("^[^@]+@[^@]+$", email))
    ])
    error_message = "iam_users must be keyed by principal email address."
  }
}

variable "builtin_users" {
  description = <<-EOT
    Break-glass password logins, username => password. The module's access
    model is IAM database authentication, so keep this empty unless a
    password login is unavoidable (legacy migration tooling, vendor support).
    Passwords are sensitive: read them from Secret Manager in the calling
    configuration instead of putting them in tfvars.
  EOT
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "databases" {
  description = "Databases created on the primary instance (replicas get them through replication), keyed by database name. Charset and collation are optional and default to the instance defaults (UTF8)."
  type = map(object({
    charset   = optional(string)
    collation = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name in keys(var.databases) : can(regex("^[a-z_][a-z0-9_]*$", name))
    ])
    error_message = "Database names must be valid PostgreSQL identifiers: lowercase letters, digits and underscores, starting with a letter or underscore."
  }
}

###############################################################################
# Standards - the same everywhere, tunable only with a reason
###############################################################################

variable "deletion_protection" {
  description = "Protect the instances from accidental deletion, both at the Terraform level (destroy is refused) and in the Cloud SQL API. Set to false only in throwaway environments."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Daily start of the backup window, UTC, HH:MM."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a UTC time in HH:MM format, for example 03:00."
  }
}

variable "backup_retention_count" {
  description = "Number of automatic daily backups to retain."
  type        = number
  default     = 7

  validation {
    condition = (
      var.backup_retention_count >= 1 &&
      var.backup_retention_count <= 365
    )
    error_message = "backup_retention_count must be between 1 and 365."
  }
}

variable "point_in_time_recovery_enabled" {
  description = "Keep write-ahead logs so the instance can be restored to any point in time. Backups themselves are always on."
  type        = bool
  default     = true
}

variable "transaction_log_retention_days" {
  description = "Days of write-ahead logs kept for point-in-time recovery."
  type        = number
  default     = 7

  validation {
    condition = (
      var.transaction_log_retention_days >= 1 &&
      var.transaction_log_retention_days <= 35
    )
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window_day" {
  description = "Day of the week the maintenance window starts, 1 (Monday) through 7 (Sunday)."
  type        = number
  default     = 7

  validation {
    condition = (
      var.maintenance_window_day >= 1 &&
      var.maintenance_window_day <= 7
    )
    error_message = "maintenance_window_day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_window_hour" {
  description = "UTC hour the maintenance window starts, 0 through 23."
  type        = number
  default     = 5

  validation {
    condition = (
      var.maintenance_window_hour >= 0 &&
      var.maintenance_window_hour <= 23
    )
    error_message = "maintenance_window_hour must be between 0 and 23."
  }
}

variable "query_insights_enabled" {
  description = "Collect per-query performance data (Query Insights), recording client addresses and application tags."
  type        = bool
  default     = true
}
