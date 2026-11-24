# ---------------------------------------------------------------------------
# Decisions the DBA team owns, instance by instance.
# Everything that should be identical on every PostgreSQL instance is fixed
# in main.tf and is intentionally NOT exposed as a variable.
# ---------------------------------------------------------------------------

variable "environment" {
  description = <<-EOT
    Which environment this instance serves. Selects the VPC the instance is
    attached to: the network team's `apps-<environment>` network, which
    already has private services access configured. The instance is created
    in the same project as that network (the provider's project).
  EOT
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "instance_name" {
  description = "Cloud SQL instance name (lowercase letters, digits, hyphens; must start with a letter)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must be 2-98 chars, start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for the instance. Choose the region the applications run in."
  type        = string
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680 or db-perf-optimized-N-2. Sizing is a DBA decision."
  type        = string

  validation {
    condition     = can(regex("^db-", var.tier))
    error_message = "tier must be a Cloud SQL machine tier beginning with \"db-\"."
  }
}

variable "database_version" {
  description = "PostgreSQL major version, e.g. POSTGRES_15. The DBA team owns version choice and upgrades."
  type        = string
  default     = "POSTGRES_15"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a PostgreSQL version such as POSTGRES_15 (this module is PostgreSQL-only by design)."
  }
}

variable "availability_type" {
  description = <<-EOT
    ZONAL (single zone) or REGIONAL (synchronous standby in a second zone).
    The DBA team decides per instance based on the workload's criticality;
    REGIONAL is recommended for production.
  EOT
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GB. Disks are SSD and grow automatically; they never shrink, so start small."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "databases" {
  description = "Application databases to create on the instance (UTF-8 / en_US.UTF8). The built-in postgres database always exists."
  type        = set(string)
  default     = []
}

variable "iam_database_users" {
  description = <<-EOT
    Google identities that log in to PostgreSQL via Cloud SQL IAM database
    authentication. Every human and workload already has a Google identity,
    and the security team audits access by those identities, so this module
    manages IAM users only -- it never creates password-based SQL users.

    Each entry: { id = "<google identity email>", type = "CLOUD_IAM_USER" or
    "CLOUD_IAM_SERVICE_ACCOUNT" }. For service accounts the module trims the
    ".gserviceaccount.com" suffix as Cloud SQL requires. Granting in-database
    privileges (GRANT/CREATE ROLE) remains the DBAs' job inside PostgreSQL.
  EOT
  type = list(object({
    id   = string
    type = string
  }))
  default = []

  validation {
    condition = alltrue([
      for u in var.iam_database_users :
      contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], u.type)
    ])
    error_message = "Each iam_database_users entry must have type CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT; built-in (password) users are not supported by this module."
  }

  validation {
    condition = alltrue([
      for u in var.iam_database_users :
      can(regex("^[^@]+@[^@]+\\.[^@]+$", u.id))
    ])
    error_message = "Each iam_database_users id must be a Google identity email address."
  }
}

variable "database_flags" {
  description = <<-EOT
    Additional PostgreSQL flags for workload tuning (DBA territory), e.g.
    { "max_connections" = "200", "log_min_duration_statement" = "1000" }.
    Flags that encode the security standard (cloudsql.iam_authentication)
    cannot be set here; the module owns them.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is a module-enforced standard and cannot be overridden via database_flags."
  }
}
