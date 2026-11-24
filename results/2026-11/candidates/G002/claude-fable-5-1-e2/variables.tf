###############################################################################
# Identity / placement
###############################################################################

variable "project_id" {
  description = "GCP project that will host the Cloud SQL instance."
  type        = string
}

variable "name" {
  description = "Base name of the instance. A short random suffix is appended by default (see use_random_suffix) because Cloud SQL reserves instance names for about a week after deletion."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,60}[a-z0-9]$", var.name))
    error_message = "name must be lowercase letters, digits and hyphens, start with a letter and end with a letter or digit."
  }
}

variable "use_random_suffix" {
  description = "Append a 4-hex-character random suffix to the instance name so the instance can be destroyed and recreated without waiting for the name reservation to expire."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment this instance serves. Selects the VPC (apps-<environment>) and drives environment-specific defaults such as high availability and backup retention."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Region for the instance (e.g. europe-west1). Must be a region where the environment VPC has a private services access range."
  type        = string
}

variable "zone" {
  description = "Preferred primary zone (e.g. europe-west1-b). Leave null to let Cloud SQL choose."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Preferred standby zone for REGIONAL instances. Leave null to let Cloud SQL choose."
  type        = string
  default     = null
}

###############################################################################
# Networking
###############################################################################

variable "network_project_id" {
  description = "Project that owns the apps-<environment> VPC (shared VPC host). Defaults to project_id."
  type        = string
  default     = null
}

variable "network_self_link" {
  description = "Override the VPC to attach to. By default the module uses projects/<network_project_id>/global/networks/apps-<environment>."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of the private services access range to allocate the instance IP from. Leave null to let Cloud SQL pick any range peered to the VPC."
  type        = string
  default     = null
}

variable "ssl_mode" {
  description = "TLS policy for client connections. Plaintext is never allowed. TRUSTED_CLIENT_CERTIFICATE_REQUIRED additionally demands a client certificate."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}

variable "connector_enforcement" {
  description = "Set to REQUIRED to only allow connections through the Cloud SQL Auth Proxy / language connectors."
  type        = string
  default     = "NOT_REQUIRED"

  validation {
    condition     = contains(["NOT_REQUIRED", "REQUIRED"], var.connector_enforcement)
    error_message = "connector_enforcement must be NOT_REQUIRED or REQUIRED."
  }
}

###############################################################################
# Engine / sizing
###############################################################################

variable "database_version" {
  description = "PostgreSQL major version, e.g. POSTGRES_16."
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
  description = "Machine tier, e.g. db-custom-2-8192 (ENTERPRISE) or db-perf-optimized-N-2 (ENTERPRISE_PLUS)."
  type        = string
  default     = "db-custom-2-8192"
}

variable "availability_type" {
  description = "ZONAL or REGIONAL (HA). Leave null for the environment default: REGIONAL in prod, ZONAL elsewhere."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["ZONAL", "REGIONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "availability_type must be ZONAL, REGIONAL or null."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GB. The disk grows automatically; later changes to the actual size are not reverted by this module."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic disk growth in GB. 0 means no limit."
  type        = number
  default     = 0
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

variable "data_cache_enabled" {
  description = "Enable the local SSD data cache (ENTERPRISE_PLUS only)."
  type        = bool
  default     = false
}

variable "database_flags" {
  description = "Additional PostgreSQL flags (name => value). Flags the module manages for everyone (cloudsql.iam_authentication, log_connections, log_disconnections) cannot be overridden."
  type        = map(string)
  default     = {}
}

variable "encryption_key_name" {
  description = "Cloud KMS key (projects/.../cryptoKeys/...) for customer-managed encryption. Null uses Google-managed encryption."
  type        = string
  default     = null
}

###############################################################################
# Backups / maintenance
###############################################################################

variable "backup_start_time" {
  description = "Daily automated backup window start, HH:MM in UTC."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM (24h, UTC)."
  }
}

variable "backup_location" {
  description = "Location for automated backups (region or multi-region). Null uses the instance's default."
  type        = string
  default     = null
}

variable "retained_backups" {
  description = "Number of automated backups to keep. Null for the environment default: 30 in prod, 7 elsewhere."
  type        = number
  default     = null
}

variable "transaction_log_retention_days" {
  description = "Days of write-ahead logs kept for point-in-time recovery (1-35)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window_day" {
  description = "Day of week for maintenance (1 = Monday ... 7 = Sunday)."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "maintenance_window_day must be 1-7."
  }
}

variable "maintenance_window_hour" {
  description = "Hour of day (UTC) for maintenance."
  type        = number
  default     = 3

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "maintenance_window_hour must be 0-23."
  }
}

variable "deny_maintenance_periods" {
  description = "Periods during which Cloud SQL must not perform maintenance (e.g. a freeze). Dates are YYYY-MM-DD; time is HH:MM:SS UTC."
  type = list(object({
    start_date = string
    end_date   = string
    time       = optional(string, "00:00:00")
  }))
  default = []
}

variable "deletion_protection" {
  description = "Prevent destruction of the instance both in OpenTofu and in the Cloud SQL API. Turn off explicitly before a planned decommission."
  type        = bool
  default     = true
}

###############################################################################
# Databases and access
###############################################################################

variable "databases" {
  description = "Databases to create on the instance. Keys are database names."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "database_deletion_policy" {
  description = "What happens to a database removed from `databases`: DELETE drops it, ABANDON only removes it from state."
  type        = string
  default     = "DELETE"

  validation {
    condition     = contains(["DELETE", "ABANDON"], var.database_deletion_policy)
    error_message = "database_deletion_policy must be DELETE or ABANDON."
  }
}

variable "iam_users" {
  description = "Google identities that may log in with IAM database authentication: user emails, group emails and service account emails. The type is inferred from the address."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+$", u))])
    error_message = "Every iam_users entry must be an email address."
  }
}

variable "iam_groups" {
  description = "Google Groups whose members may log in with IAM group authentication (each member logs in as themselves)."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for g in var.iam_groups : can(regex("^[^@\\s]+@[^@\\s]+$", g))])
    error_message = "Every iam_groups entry must be a group email address."
  }
}

variable "grant_iam_login_roles" {
  description = "Grant roles/cloudsql.instanceUser and roles/cloudsql.client on the project to every identity in iam_users and iam_groups so they can actually connect. Disable if those roles are managed elsewhere."
  type        = bool
  default     = true
}

variable "break_glass_admin" {
  description = "Name of a password-authenticated admin user to create for emergencies (e.g. \"dba_admin\"). Its password is generated and stored in Secret Manager. Null (the default) creates no password users at all."
  type        = string
  default     = null
}

###############################################################################
# Metadata
###############################################################################

variable "labels" {
  description = "Extra labels applied to the instance and related resources."
  type        = map(string)
  default     = {}
}
