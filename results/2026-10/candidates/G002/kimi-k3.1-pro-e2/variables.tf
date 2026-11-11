variable "project_id" {
  description = "ID of the Google Cloud project in which the Cloud SQL instance is created."
  type        = string

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for the instance, for example us-central1."
  type        = string

  validation {
    condition     = length(trimspace(var.region)) > 0
    error_message = "region must not be empty."
  }
}

variable "instance_name" {
  description = "Cloud SQL instance name, unique within the project."
  type        = string

  validation {
    condition = (
      length(var.instance_name) <= 63 &&
      can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.instance_name))
    )
    error_message = "instance_name must be at most 63 characters, start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "network_self_link" {
  description = "Self link of an existing VPC with private services access, in the form projects/PROJECT/global/networks/NETWORK. The module does not manage the VPC, peering, or allocated ranges."
  type        = string

  validation {
    condition     = can(regex("^(https://www.googleapis.com/compute/v1/)?projects/[^/]+/global/networks/[^/]+$", var.network_self_link))
    error_message = "network_self_link must be a full or partial VPC self link such as projects/my-project/global/networks/apps-dev."
  }
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version. New major versions can be adopted without changing the module."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version such as POSTGRES_16."
  }
}

variable "edition" {
  description = "Cloud SQL edition. Choose ENTERPRISE_PLUS only with a machine series and storage supported by that edition."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier. DBAs can select a predefined or custom tier appropriate to the workload."
  type        = string
  default     = "db-custom-2-7680"

  validation {
    condition     = length(trimspace(var.tier)) > 0
    error_message = "tier must not be empty."
  }
}

variable "availability_type" {
  description = "ZONAL for a single-zone instance or REGIONAL for synchronous high availability."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "zone" {
  description = "Optional preferred primary zone. When omitted, Cloud SQL selects a zone in the region."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.zone == null || length(trimspace(var.zone)) > 0
    error_message = "zone must be null or a nonempty zone name."
  }
}

variable "disk_type" {
  description = "Persistent disk type. HYPERDISK_BALANCED is available only for compatible Enterprise Plus configurations."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be PD_SSD, PD_HDD, or HYPERDISK_BALANCED."
  }
}

variable "disk_size" {
  description = "Initial data disk size in GiB. Changes to a larger size are supported; Cloud SQL does not support shrinking disks."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size >= 10 && floor(var.disk_size) == var.disk_size
    error_message = "disk_size must be a whole number of at least 10 GiB."
  }
}

variable "disk_autoresize" {
  description = "Whether Cloud SQL automatically increases storage capacity before the disk fills."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "Maximum autoresize capacity in GiB; 0 means no module-imposed limit. A nonzero limit cannot be smaller than disk_size."
  type        = number
  default     = 0

  validation {
    condition = (
      var.disk_autoresize_limit >= 0 &&
      floor(var.disk_autoresize_limit) == var.disk_autoresize_limit &&
      (var.disk_autoresize_limit == 0 || var.disk_autoresize_limit >= var.disk_size)
    )
    error_message = "disk_autoresize_limit must be a whole number and either 0 or at least disk_size."
  }
}

variable "backup" {
  description = <<-EOT
    Automated backup and point-in-time recovery policy. Backups and PITR are always enabled.
    start_time is UTC in HH:MM format. location=null lets Cloud SQL select the backup location.
    retained_backups is the number of automated backups retained (1-365).
  EOT
  type = object({
    start_time                     = optional(string, "02:00")
    location                       = optional(string)
    retained_backups               = optional(number, 35)
    transaction_log_retention_days = optional(number, 7)
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup.start_time))
    error_message = "backup.start_time must use 24-hour HH:MM format."
  }

  validation {
    condition     = var.backup.retained_backups >= 1 && var.backup.retained_backups <= 365 && floor(var.backup.retained_backups) == var.backup.retained_backups
    error_message = "backup.retained_backups must be a whole number from 1 through 365."
  }

  validation {
    condition     = var.backup.transaction_log_retention_days >= 1 && var.backup.transaction_log_retention_days <= 7 && floor(var.backup.transaction_log_retention_days) == var.backup.transaction_log_retention_days
    error_message = "backup.transaction_log_retention_days must be a whole number from 1 through 7."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance window. day uses 1=Monday through 7=Sunday; hour is 0-23. Update track remains stable for every instance."
  type = object({
    day  = optional(number, 7)
    hour = optional(number, 3)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day
    error_message = "maintenance_window.day must be a whole number from 1 (Monday) through 7 (Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour
    error_message = "maintenance_window.hour must be a whole number from 0 through 23."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL database flags, as a map of flag name to string value. Standard connection/audit logging defaults can be tuned, but cloudsql.iam_authentication cannot be disabled."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "labels" {
  description = "Additional resource labels. The managed_by=opentofu label is always applied."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "databases" {
  description = <<-EOT
    Additional PostgreSQL databases keyed by database name. The default postgres database is managed by Cloud SQL and is not declared here.
    charset defaults to UTF8, collation uses the Cloud SQL default when null, and deletion_policy defaults to ABANDON to avoid accidental data loss.
  EOT
  type = map(object({
    charset         = optional(string, "UTF8")
    collation       = optional(string)
    deletion_policy = optional(string, "ABANDON")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.databases) : length(name) > 0 && length(name) <= 63])
    error_message = "Every database name must contain between 1 and 63 characters."
  }

  validation {
    condition     = alltrue([for db in values(var.databases) : contains(["ABANDON", "DELETE"], db.deletion_policy)])
    error_message = "Each database deletion_policy must be ABANDON or DELETE."
  }
}

variable "iam_users" {
  description = <<-EOT
    IAM identities to create as PostgreSQL users, keyed by full identity email. Values must be CLOUD_IAM_USER for people or CLOUD_IAM_SERVICE_ACCOUNT for workloads.
    The module grants each principal roles/cloudsql.instanceUser and roles/cloudsql.client at project scope through non-authoritative IAM member resources.
  EOT
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for user_type in values(var.iam_users) : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], user_type)])
    error_message = "Each iam_users value must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }

  validation {
    condition     = alltrue([for email in keys(var.iam_users) : can(regex("^[^@\\s]+@[^@\\s]+$", email))])
    error_message = "Each iam_users key must be a full Google user or service account email address."
  }
}

variable "deletion_protection" {
  description = "Protect the instance against deletion at both the Cloud SQL API and OpenTofu layers. Set false and apply before destroying an instance deliberately."
  type        = bool
  default     = true
}
