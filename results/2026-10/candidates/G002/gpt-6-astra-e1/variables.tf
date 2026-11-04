variable "project_id" {
  description = "Existing Google Cloud project with the Cloud SQL Admin API enabled."
  type        = string
}

variable "name" {
  description = "Cloud SQL instance name; changing it replaces the instance."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.name))
    error_message = "Use a 2-98 character lowercase Cloud SQL instance name, starting with a letter and ending in a letter or digit."
  }
}

variable "region" {
  description = "Region for the instance and its backups (data-residency decision)."
  type        = string
}

variable "private_network" {
  description = "Existing VPC resource path: projects/PROJECT/global/networks/apps-dev, apps-staging or apps-prod. Private services access must already exist. Shared VPC host projects are supported."
  type        = string
  validation {
    condition     = can(regex("^(https://www.googleapis.com/compute/v1/)?projects/[^/]+/global/networks/apps-(dev|staging|prod)$", var.private_network))
    error_message = "Select the existing apps-dev, apps-staging or apps-prod VPC using its full resource path or self link."
  }
}

variable "postgres_version" {
  description = "DBA-selected PostgreSQL major version, e.g. POSTGRES_16. Upgrades are deliberate; Cloud SQL does not support downgrades."
  type        = string
  validation {
    condition     = can(regex("^POSTGRES_(1[4-9]|[2-9][0-9])$", var.postgres_version))
    error_message = "Use POSTGRES_14 or newer; the chosen version must be supported in Cloud SQL."
  }
}

variable "tier" {
  description = "DBA-selected Enterprise edition machine tier, e.g. db-custom-2-7680. Must support the chosen version and availability type."
  type        = string
}

variable "availability_type" {
  description = "REGIONAL HA is the standard. DBAs may explicitly select ZONAL for noncritical instances."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Choose REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD capacity; Cloud SQL can increase but cannot shrink disks. Automatic growth is always enabled without a cap."
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Disk size must be an integer from 10 to 65536 GB."
  }
}

variable "maintenance_window" {
  description = "UTC maintenance window: day 1 is Monday, 7 is Sunday. Stable update track is fixed."
  type = object({
    day  = number
    hour = number
  })
  default = { day = 7, hour = 3 }
  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day && var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour
    error_message = "Maintenance day must be an integer 1-7 and hour an integer 0-23."
  }
}

variable "backup_start_time" {
  description = "Daily backup start time in UTC; retention and PITR are standardized."
  type        = string
  default     = "01:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Use HH:MM in UTC."
  }
}

variable "database_flags" {
  description = "DBA-owned PostgreSQL flags. IAM database authentication cannot be overridden. Some changes restart the instance."
  type        = map(string)
  default     = {}
  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is mandatory and managed by this module."
  }
}

variable "databases" {
  description = "Databases keyed by name; encoding and collation are creation-time decisions. No application databases are created unless requested."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "iam_users" {
  description = "Identity email => USER or SERVICE_ACCOUNT. Supply full service-account emails including .gserviceaccount.com. Creates IAM database users and instance-scoped IAM grants; never creates passwords or shared logins. PostgreSQL object privileges remain a DBA responsibility."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for email, kind in var.iam_users :
      contains(["USER", "SERVICE_ACCOUNT"], kind) &&
      email == lower(email) &&
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email)) &&
      (kind == "SERVICE_ACCOUNT" ? endswith(email, ".gserviceaccount.com") : !endswith(email, ".gserviceaccount.com"))
    ])
    error_message = "Use lowercase identity emails and USER or SERVICE_ACCOUNT, with full .gserviceaccount.com emails for service accounts."
  }
}

variable "labels" {
  description = "Additional Cloud SQL labels; managed_by is reserved."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protects against both OpenTofu and API/console deletion. Set false and apply before an intentional destroy; take a final backup first."
  type        = bool
  default     = true
}
