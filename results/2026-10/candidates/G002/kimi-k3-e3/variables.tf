# ---------------------------------------------------------------------------
# Inputs without defaults: the decisions that are genuinely per-instance.
# Every one of these must be supplied by the caller (see minimal.tfvars for
# the smallest valid instantiation).
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project in which the Cloud SQL instance is created."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "Region in which the instance runs, e.g. \"europe-west1\"."
  type        = string
}

variable "instance_name" {
  description = "Name of the Cloud SQL instance."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,97}$", var.instance_name))
    error_message = "instance_name must be 1-98 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "network_self_link" {
  description = <<-EOT
    Self link of the environment VPC network (apps-dev, apps-staging or
    apps-prod) from which the instance gets its private IP, in the form
    "projects/<project>/global/networks/<network>". The network team owns
    these networks and has already configured private services access on
    them; this module only attaches the instance.
  EOT
  type        = string

  validation {
    condition     = can(regex("^projects/[^/]+/global/networks/[^/]+$", var.network_self_link))
    error_message = "network_self_link must be of the form projects/<project>/global/networks/<network>."
  }
}

# ---------------------------------------------------------------------------
# Inputs with defaults: DBA decisions, pre-decided to the team standard so
# they only need to be set when an instance genuinely deviates.
# ---------------------------------------------------------------------------

variable "database_version" {
  description = "PostgreSQL major version, e.g. \"POSTGRES_16\"."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be of the form POSTGRES_<major version>, e.g. POSTGRES_16."
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
  description = "Machine tier of the instance, e.g. \"db-custom-4-16384\"."
  type        = string
  default     = "db-custom-2-8192"

  validation {
    condition     = can(regex("^db-", var.tier))
    error_message = "tier must be a Cloud SQL machine tier, e.g. db-custom-4-16384."
  }
}

variable "availability_type" {
  description = "REGIONAL keeps the instance highly available across zones; ZONAL runs a single-zone instance (suitable for throwaway dev databases)."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD/HDD size in GB. Storage autoresize is always on, so this is a floor, not a ceiling."
  type        = number
  default     = 50

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "disk_size_gb must be between 10 and 65536."
  }
}

variable "disk_type" {
  description = "Storage type: PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound (GB) for automatic storage growth. 0 means no limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0
    error_message = "disk_autoresize_limit_gb must be greater than or equal to 0."
  }
}

variable "allocated_ip_range" {
  description = "Name of the allocated IP range on the VPC to draw the private IP from, if the network team assigned a specific one. Null lets Google pick from the private services access range."
  type        = string
  default     = null
}

variable "ssl_mode" {
  description = "How strictly clients must connect over TLS. The standard is ENCRYPTED_ONLY."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ALLOW_UNENCRYPTED_AND_ENCRYPTED", "ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be ALLOW_UNENCRYPTED_AND_ENCRYPTED, ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}

variable "encryption_key_name" {
  description = "Optional self link of a Cloud KMS key for customer-managed encryption (CMEK). Null uses Google-managed keys. When set, the project's Cloud SQL service agent must already have encrypt/decrypt rights on the key."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Protect the instance against accidental deletion. Keep this true for anything that holds data you care about."
  type        = bool
  default     = true
}

variable "labels" {
  description = "User labels to apply to the instance (e.g. environment, team, cost centre)."
  type        = map(string)
  default     = {}
}

variable "database_flags" {
  description = "Additional PostgreSQL flags as name => value (e.g. { \"max_connections\" = \"200\" }). The module always enforces cloudsql.iam_authentication=on; it cannot be overridden here."
  type        = map(string)
  default     = {}
}

variable "backup" {
  description = <<-EOT
    Backup schedule and retention. The team standard (the defaults) is daily
    backups at 02:00 UTC with point-in-time recovery and 14 retained backups.
    start_time is HH:MM (24h, UTC) and marks the start of the backup window.
  EOT
  type = object({
    enabled                        = optional(bool, true)
    start_time                     = optional(string, "02:00")
    point_in_time_recovery_enabled = optional(bool, true)
    transaction_log_retention_days = optional(number, 7)
    retained_backups               = optional(number, 14)
  })
  default = {}

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup.start_time))
    error_message = "backup.start_time must be in HH:MM 24-hour format."
  }

  validation {
    condition     = var.backup.transaction_log_retention_days >= 1 && var.backup.transaction_log_retention_days <= 7
    error_message = "backup.transaction_log_retention_days must be between 1 and 7."
  }

  validation {
    condition     = var.backup.retained_backups >= 1 && var.backup.retained_backups <= 365
    error_message = "backup.retained_backups must be between 1 and 365."
  }
}

variable "maintenance_window" {
  description = "Preferred maintenance window: day 1-7 (1 = Monday, 7 = Sunday), hour 0-23. The standard is Sunday 03:00 on the stable update track."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7
    error_message = "maintenance_window.day must be between 1 (Monday) and 7 (Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.hour must be between 0 and 23."
  }

  validation {
    condition     = contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be canary, stable or week5."
  }
}

variable "databases" {
  description = "Databases to create on the instance, keyed by database name. The default postgres database always exists and is managed by Cloud SQL itself."
  type = map(object({
    charset   = optional(string)
    collation = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for name in keys(var.databases) : can(regex("^[A-Za-z][A-Za-z0-9_-]{0,62}$", name))])
    error_message = "Database names must start with a letter and contain only letters, digits, underscores and hyphens (max 63 characters)."
  }
}

variable "iam_users" {
  description = <<-EOT
    Google identities that receive a database login through Cloud SQL IAM
    authentication, keyed by a logical name. Access is audited by Google
    identity, so every engineer and every workload gets their own entry:

      iam_users = {
        alice  = { email = "alice@example.com" }                                  # CLOUD_IAM_USER (default)
        orders = { email = "orders@prj.iam.gserviceaccount.com",
                   type  = "CLOUD_IAM_SERVICE_ACCOUNT" }
      }
  EOT
  type = map(object({
    email = string
    type  = optional(string, "CLOUD_IAM_USER")
  }))
  default = {}

  validation {
    condition     = alltrue([for u in var.iam_users : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT", "CLOUD_IAM_GROUP"], u.type)])
    error_message = "iam_users type must be CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT or CLOUD_IAM_GROUP."
  }

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("@", u.email))])
    error_message = "Every iam_users entry must have an email address."
  }
}
