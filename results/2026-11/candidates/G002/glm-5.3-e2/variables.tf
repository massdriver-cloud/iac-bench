# =============================================================================
# Required inputs — the decisions that are genuinely the DBA team's
#
# Identity, placement, capacity, connectivity and who connects differ from
# database to database, so they are supplied on every instantiation.
# Everything below them has a default that implements the team's standards.
# =============================================================================

variable "name" {
  description = "Name of the primary Cloud SQL instance. Lowercase letters, digits and hyphens, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}$", var.name))
    error_message = "name must start with a lowercase letter and may only contain lowercase letters, digits and hyphens (1-97 characters)."
  }
}

variable "region" {
  description = "Region for the primary instance, e.g. us-central1. Read replicas default to this region and may override it for cross-region replicas."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)+$", var.region))
    error_message = "region must be a Google Cloud region such as us-central1 or europe-west4."
  }
}

variable "network" {
  description = <<-EOT
    Self link of the VPC network the instance attaches to over private
    services access, e.g. projects/my-project/global/networks/apps-prod
    (the full compute.googleapis.com URL form also works).

    The network team owns one custom VPC per environment (apps-dev,
    apps-staging, apps-prod) and has already configured private services
    access. This module only consumes the network — it never creates or
    changes networks, peerings or allocated ranges.
  EOT
  type        = string

  validation {
    condition     = can(regex("global/networks/", var.network))
    error_message = "network must be a network self link (projects/<project>/global/networks/<name> or the full URL), not a bare network name."
  }
}

variable "environment" {
  description = "Environment this instance serves: dev, staging or prod. Chooses the module's environment policy (high availability, point-in-time recovery, insights) and is written as the environment label."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "tier" {
  description = "Compute tier for the primary instance, e.g. db-custom-2-7680 (2 vCPU / 7.5 GB); db-perf-optimized-* tiers for the Enterprise Plus edition."
  type        = string

  validation {
    condition     = can(regex("^db-", var.tier))
    error_message = "tier must be a Cloud SQL tier name, e.g. db-custom-2-7680."
  }
}

# =============================================================================
# Optional inputs — the defaults are the standard; override with a reason
# =============================================================================

variable "project" {
  description = "Project for the instance. Leave unset (null) to use the project configured on the Google provider — instances belong in the same project as the networks they attach to, so this should rarely be set."
  type        = string
  default     = null
}

variable "database_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = contains(["POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "database_version must be one of POSTGRES_13 ... POSTGRES_17."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE (db-custom tiers) or ENTERPRISE_PLUS (db-perf-optimized tiers)."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "zone" {
  description = "Pin the primary instance to a specific zone within var.region (e.g. to co-locate it with a GKE node pool); null lets Cloud SQL choose."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || can(regex("^[a-z0-9]+(-[a-z0-9]+)*-[a-z]$", var.zone))
    error_message = "zone must look like a Google Cloud zone, e.g. us-central1-a."
  }
}

variable "disk_size_gb" {
  description = "Initial disk size in GB for the primary instance; auto-resize is on by default. Read replicas default to this unless overridden per replica."
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be a whole number of at least 10 (GB)."
  }
}

variable "disk_type" {
  description = "Disk type: PD_SSD (default) or PD_HDD."
  type        = string
  default     = "PD_SSD"
}

variable "disk_autoresize" {
  description = "Grow the disk automatically when it fills. Turning this off makes disk_size_gb a hard limit."
  type        = bool
  default     = true
}

variable "availability_type" {
  description = "High availability: REGIONAL (synchronous standby in a second zone, automatic failover) or ZONAL (single zone). null (default) follows the environment policy — REGIONAL everywhere except dev."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "point_in_time_recovery_enabled" {
  description = "Point-in-time recovery (transaction log retention on top of automated backups). null (default) follows the environment policy: on in staging and prod, off in dev."
  type        = bool
  default     = null
}

variable "query_insights_enabled" {
  description = "Query Insights on the instance. null (default) follows the environment policy (on everywhere)."
  type        = bool
  default     = null
}

variable "backup_start_time" {
  description = "UTC start of the automated backup window, HH:MM (the window is four hours long)."
  type        = string
  default     = "06:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a UTC HH:MM time, e.g. 06:00."
  }
}

variable "backup_retention_days" {
  description = "Automated backups to retain; for PostgreSQL this is days (1-35)."
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Maintenance window in UTC: day 1 (Monday) to 7 (Sunday), hour 0-23, and update track stable or canary. Default: Sunday 07:00 UTC on the stable track."
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
    error_message = "maintenance_window.day must be 1 (Monday) through 7 (Sunday)."
  }
  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.hour must be 0-23 (UTC)."
  }
  validation {
    condition     = contains(["stable", "canary"], var.maintenance_window.update_track)
    error_message = "maintenance_window.update_track must be stable or canary."
  }
}

variable "database_flags" {
  description = "PostgreSQL server parameters, e.g. { max_connections = \"200\", work_mem = \"64MB\" }. Values are strings. The module always merges cloudsql.iam_authentication = on — IAM logins are the standard and cannot be disabled."
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication") || var.database_flags["cloudsql.iam_authentication"] == "on"
    error_message = "cloudsql.iam_authentication is enforced by the module (IAM database authentication is the authentication standard) and cannot be set to off."
  }
}

variable "databases" {
  description = "Databases to create on the instance. The map key is the database name; charset and collation default to UTF8 / en_US.UTF8."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}

  validation {
    condition     = alltrue([for name, _ in var.databases : can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", name))])
    error_message = "database names must be valid PostgreSQL identifiers (letters, digits, underscore, starting with a letter or underscore)."
  }
}

variable "iam_users" {
  description = "Emails of engineers who log in to the database with their own Google identity. The module creates a CLOUD_IAM_USER for each. Password-based logins do not exist in this module."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", u))])
    error_message = "iam_users must contain user email addresses."
  }
}

variable "iam_service_accounts" {
  description = "Service account emails of the workloads that connect (GKE / Compute Engine), authenticated with their Google identity. The module creates a CLOUD_IAM_SERVICE_ACCOUNT database user for each."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_service_accounts : can(regex("^[^@ ]+@[^@ ]+\\.iam\\.gserviceaccount\\.com$", u))])
    error_message = "iam_service_accounts must contain Google service account emails (…@<project>.iam.gserviceaccount.com)."
  }
}

variable "manage_iam_grants" {
  description = "Grant roles/cloudsql.instanceUser (the cloudsql.instances.login permission IAM database logins need) and roles/cloudsql.client (connector/proxy discovery) in the project to every listed identity, as non-authoritative bindings. Set false if a central team owns IAM — the database users are still created."
  type        = bool
  default     = true
}

variable "read_replicas" {
  description = "Read replicas, keyed by instance name. region enables cross-region replicas; disk settings default to the primary's. Replicas inherit the network, TLS and flag policy."
  type = map(object({
    tier         = string
    region       = optional(string)
    disk_size_gb = optional(number)
    disk_type    = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for name, _ in var.read_replicas : can(regex("^[a-z][a-z0-9-]{0,96}$", name))])
    error_message = "read replica names must follow Cloud SQL instance naming rules (lowercase letters, digits, hyphens)."
  }
  validation {
    condition     = alltrue([for r in var.read_replicas : can(regex("^db-", r.tier))])
    error_message = "read_replicas tiers must be Cloud SQL tier names, e.g. db-custom-4-15360."
  }
}

variable "kms_key_name" {
  description = "Customer-managed encryption key (self link). null (default) uses Google-managed encryption. Before the first apply, grant the instance's Cloud SQL service account (service_account_email_address output) roles/cloudkms.cryptoKeyEncrypterDecrypter on this key."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^(https://[^/]+/)?projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be a KMS key self link (projects/<p>/locations/<l>/keyRings/<k>/cryptoKeys/<n>)."
  }
}

variable "allocated_ip_range" {
  description = "Name of the allocated range (created by the network team on the VPC) from which this instance's private IP is carved — use it when the network team pre-allocates deterministic ranges per service. null (default) uses any range available through the private services access peering."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional labels for every instance the module creates, merged under the module's standard labels (environment, managed_by)."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "label keys and values may only contain lowercase letters, digits, dashes and underscores (max 63 characters)."
  }
}

variable "deletion_protection" {
  description = "Guards every instance the module creates: enables Cloud SQL deletion protection and the Terraform destroy guard. Flip to false only as the final step of a decommission — see the README runbook."
  type        = bool
  default     = true
}
