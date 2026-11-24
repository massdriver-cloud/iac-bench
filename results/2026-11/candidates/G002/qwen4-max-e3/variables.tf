# ---------------------------------------------------------------------------
# Decisions the DBA team owns, per instance.
# ---------------------------------------------------------------------------

variable "instance_name" {
  description = "Cloud SQL instance ID. Lowercase letters, digits and hyphens; must start with a letter and end with a letter or digit."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must be 2-98 chars, lowercase letters/digits/hyphens, start with a letter and end with a letter or digit."
  }
}

variable "environment" {
  description = "Environment this instance belongs to. Selects the apps-<environment> VPC (owned by the network team, private services access already configured) and the environment's HA/backup/update-track policy."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Google Cloud region for the instance. Must be the region the environment's apps-* network and private services access serve."
  type        = string
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680 or db-perf-optimized-N-2. Sizing is a DBA decision; the module does not pick it for you."
  type        = string

  validation {
    condition     = can(regex("^db-", var.tier))
    error_message = "tier must be a Cloud SQL machine tier beginning with \"db-\"."
  }
}

variable "database_name" {
  description = "Application database created inside the instance (UTF8 / en_US.UTF8, the team standard)."
  type        = string

  validation {
    condition     = length(var.database_name) > 0 && length(var.database_name) <= 63
    error_message = "database_name must be 1-63 characters."
  }
}

# ---------------------------------------------------------------------------
# DBA-owned knobs with team-standard defaults.
# ---------------------------------------------------------------------------

variable "database_version" {
  description = "PostgreSQL major version. Defaults to the team-standard version; override only for a deliberate version decision."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_1[3-7]$", var.database_version))
    error_message = "database_version must be a supported Cloud SQL PostgreSQL version (POSTGRES_13 .. POSTGRES_17)."
  }
}

variable "iam_database_users" {
  description = "Google identities granted database login via Cloud SQL IAM authentication. type is CLOUD_IAM_USER (engineers) or CLOUD_IAM_SERVICE_ACCOUNT (workloads). No password users are created by this module."
  type = list(object({
    email = string
    type  = string
  }))
  default = []

  validation {
    condition = alltrue([
      for u in var.iam_database_users :
      contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], u.type)
    ])
    error_message = "Each iam_database_users entry must have type CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL flags for workload-specific tuning. The team's mandatory flags (IAM auth, audit logging) are always applied and cannot be overridden here."
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is enforced by the module and cannot be set via database_flags."
  }
}

variable "labels" {
  description = "Extra user labels merged onto the team-standard labels (environment, managed-by)."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protect the instance from accidental deletion (both OpenTofu-level and Cloud SQL API-level). Standard is true; set false only for deliberately disposable instances."
  type        = bool
  default     = true
}
