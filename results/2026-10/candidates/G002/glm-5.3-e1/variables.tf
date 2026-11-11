###############################################################################
# Required: identity and placement of the instance
###############################################################################

variable "project_id" {
  description = <<-EOT
    Google Cloud project that owns the Cloud SQL instance.

    Unless network_project_id is set, this project is also expected to contain
    the apps-<environment> network, with private services access already
    configured on it by the network team.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid project id: 6-30 characters, lowercase letters, digits and hyphens."
  }
}

variable "name" {
  description = <<-EOT
    Name of the Cloud SQL instance, e.g. orders-db. Keep the name about the
    workload; the environment is carried by the environment variable, the
    environment label and the network the instance lands in.
  EOT
  type        = string

  validation {
    condition     = can(regex("^([a-z]|[a-z][a-z0-9-]*[a-z0-9])$", var.name)) && length(var.name) <= 97
    error_message = "name must be 1-97 characters, lowercase letters, digits and hyphens; it must start with a letter and must not end with a hyphen."
  }
}

variable "region" {
  description = "Region the instance lives in, e.g. us-central1 or europe-west3."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+(-[a-z]+)+[0-9]$", var.region))
    error_message = "region must be a Google Cloud region such as us-central1."
  }
}

variable "environment" {
  description = <<-EOT
    Environment the instance serves: dev, staging or prod.

    It decides which custom VPC the instance is attached to (apps-<environment>,
    where the network team has already configured private services access),
    the availability and backup-retention policy, and the environment label.
  EOT
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

###############################################################################
# Networking: private IP only - not a per-instance decision
###############################################################################

variable "network_project_id" {
  description = <<-EOT
    Project that hosts the apps-<environment> network. Leave unset when the
    networks live in the same project as the instance; set it when the network
    team keeps them in a separate (Shared VPC host) project.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.network_project_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.network_project_id))
    error_message = "network_project_id must be a valid project id."
  }
}

###############################################################################
# Sizing and availability: per-instance DBA decisions
###############################################################################

variable "tier" {
  description = <<-EOT
    Compute tier as a custom machine type, db-custom-<vCPUs>-<memory MB>, for
    example db-custom-2-7680 (2 vCPUs, 7.5 GiB). Custom types are the standard
    here so that CPU and memory can be sized independently of each other.
  EOT
  type        = string
  default     = "db-custom-2-7680"

  validation {
    condition     = can(regex("^db-custom-[0-9]+-[0-9]+$", var.tier))
    error_message = "tier must be a custom machine type, e.g. db-custom-2-7680."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE (the default) or ENTERPRISE_PLUS (storage autoscaling, faster failover, at a premium)."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = <<-EOT
    ZONAL or REGIONAL (high availability). Leave unset to follow the
    environment policy: REGIONAL for staging and prod, ZONAL for dev. Override
    only with a reason, e.g. a dev instance that must survive a zone loss.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL, or unset to follow the environment policy."
  }
}

variable "disk_type" {
  description = "PD_SSD (the standard for a database) or PD_HDD for a throwaway instance."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_size_gb" {
  description = <<-EOT
    Initial data disk size in GB. Storage auto-resize is always enabled, so
    this is only the starting point: Cloud SQL grows the disk on demand, and
    a disk cannot be shrunk.
  EOT
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 30720
    error_message = "disk_size_gb must be between 10 and 30720."
  }
}

variable "preferred_zone" {
  description = "Optional zone to place the instance in (for a REGIONAL instance, its primary zone), e.g. us-central1-a."
  type        = string
  default     = null

  validation {
    condition     = var.preferred_zone == null || can(regex("^[a-z]+(-[a-z]+)+[0-9]-[a-z]$", var.preferred_zone))
    error_message = "preferred_zone must be a Google Cloud zone such as us-central1-a, or unset."
  }
}

###############################################################################
# PostgreSQL: per-instance DBA decisions
###############################################################################

variable "major_version" {
  description = "PostgreSQL major version. The module derives the Cloud SQL version string from it (POSTGRES_<major_version>)."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["15", "16", "17"], var.major_version)
    error_message = "major_version must be one of the PostgreSQL versions the team supports: 15, 16 or 17."
  }
}

variable "database_flags" {
  description = <<-EOT
    PostgreSQL database flags, e.g. { "max_connections" = "200" }. The module
    always sets cloudsql.iam_authentication=on and rejects any attempt to set
    that flag here.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is always on in this module; it cannot be set through database_flags."
  }
}

###############################################################################
# Care and feeding: backups, point-in-time recovery, maintenance
###############################################################################

variable "backup_start_time" {
  description = "UTC start of the daily backup window, HH:MM."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a UTC time in HH:MM form, e.g. 03:00."
  }
}

variable "backup_retention_days" {
  description = "Days to retain automated backups. Leave unset to follow the environment policy (dev 7, staging 14, prod 30)."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_days == null || (var.backup_retention_days >= 1 && var.backup_retention_days <= 365)
    error_message = "backup_retention_days must be between 1 and 365, or unset to follow the environment policy."
  }
}

variable "pitr_enabled" {
  description = "Point-in-time recovery. On by default in every environment."
  type        = bool
  default     = true
}

variable "transaction_log_retention_days" {
  description = "Days of transaction logs kept for point-in-time recovery. Leave unset to follow the environment policy (dev 1, staging 7, prod 7)."
  type        = number
  default     = null

  validation {
    condition     = var.transaction_log_retention_days == null || (var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35)
    error_message = "transaction_log_retention_days must be between 1 and 35, or unset to follow the environment policy."
  }
}

variable "maintenance_window_day" {
  description = "Day of the maintenance window: 1 (Monday) through 7 (Sunday). Default 7 (Sunday)."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "maintenance_window_day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_window_hour" {
  description = "UTC hour the maintenance window starts. Default 07:00, deliberately clear of the 03:00 backup window."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "maintenance_window_hour must be between 0 and 23."
  }
}

###############################################################################
# Access: Google identities only
###############################################################################

variable "iam_users" {
  description = <<-EOT
    Google identities (people) who may log in to PostgreSQL with their own
    credentials, e.g. jane.doe@acme.com. Each becomes an IAM database user on
    the instance and is granted the roles/cloudsql.instanceUser login
    permission in the instance's project.

    Cloud SQL IAM database authentication does not support Google Groups, so
    engineers are listed individually - exactly the identity-level view the
    security team audits.
  EOT
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for user in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+$", user)) && lower(user) == user
    ])
    error_message = "Every iam_users entry must be a lowercase email address (PostgreSQL folds unquoted identifiers to lowercase, so Cloud SQL requires lowercase IAM user names)."
  }
}

variable "iam_service_accounts" {
  description = <<-EOT
    Service accounts of the workloads (GKE workloads, Compute Engine VMs) that
    connect to the instance, e.g.
    orders-api@acme-apps-dev.iam.gserviceaccount.com. Each becomes an IAM
    database user on the instance and is granted the roles/cloudsql.instanceUser
    login permission in the instance's project.

    The project-level roles/cloudsql.client grant that the Cloud SQL
    connectors need in order to fetch instance metadata stays with the
    platform teams that own the workload projects.
  EOT
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for sa in var.iam_service_accounts : can(regex("^[^@\\s]+@[^@\\s]+$", sa)) && lower(sa) == sa
    ])
    error_message = "Every iam_service_accounts entry must be a lowercase service account email address."
  }
}

variable "databases" {
  description = "Databases to create on the instance. They get PostgreSQL's default charset and collation."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for database in var.databases : can(regex("^[a-z_][a-z0-9_]*$", database))
    ]) && !contains(var.databases, "postgres")
    error_message = "Database names must be valid unquoted PostgreSQL identifiers (lowercase) and must not be the built-in postgres database."
  }
}

###############################################################################
# Labels
###############################################################################

variable "labels" {
  description = "Extra labels for the instance. The module always sets environment and managed_by; those two keys are reserved."
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.labels), "environment") && !contains(keys(var.labels), "managed_by")
    error_message = "The labels environment and managed_by are set by the module and cannot be overridden."
  }

  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z0-9_-]{1,63}$", key)) && can(regex("^[a-z0-9_-]{0,63}$", value))
    ])
    error_message = "Labels must be valid Google Cloud labels: lowercase letters, digits, underscores and hyphens."
  }
}
