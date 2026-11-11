variable "project_id" {
  description = "Existing project with the Cloud SQL Admin API enabled. Credentials come from the environment."
  type        = string
}

variable "name" {
  description = "Cloud SQL instance name. Changing this replaces the instance."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.name))
    error_message = "Use 2-98 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "region" {
  description = "Region for the database, normally colocated with its applications."
  type        = string
}

variable "network" {
  description = "Existing environment VPC resource path: projects/PROJECT/global/networks/apps-dev, apps-staging or apps-prod. Private services access must already exist to the SQL project. Shared VPC host project paths are supported."
  type        = string
  validation {
    condition     = can(regex("^projects/[^/]+/global/networks/apps-(dev|staging|prod)$", var.network))
    error_message = "Supply the resource path of the existing apps-dev, apps-staging or apps-prod VPC."
  }
}

variable "postgres_version" {
  description = "Cloud SQL PostgreSQL major version. Upgrading is an explicit DBA decision; downgrades are not supported."
  type        = string
  default     = "POSTGRES_16"
  validation {
    condition     = contains(["POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.postgres_version)
    error_message = "Choose a supported PostgreSQL major version: 14, 15, 16 or 17."
  }
}

variable "tier" {
  description = "Enterprise-edition machine tier; use a regional-HA compatible tier when availability_type is REGIONAL."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "REGIONAL provides automatic zonal failover. ZONAL explicitly trades availability for cost."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Use REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD size in GB. Cloud SQL can grow but cannot shrink disks. Automatic growth is always enabled."
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "Disk size must be an integer of at least 10 GB."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance UTC window: day 1=Monday through 7=Sunday."
  type = object({
    day  = number
    hour = number
  })
  default = { day = 7, hour = 3 }
  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && floor(var.maintenance_window.day) == var.maintenance_window.day &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 && floor(var.maintenance_window.hour) == var.maintenance_window.hour
    )
    error_message = "Maintenance day must be an integer 1-7 and hour an integer 0-23."
  }
}

variable "backup_start_time" {
  description = "Daily backup start time in UTC. Backups, 14 retained backups and 7-day PITR are mandatory."
  type        = string
  default     = "01:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Use HH:MM in UTC."
  }
}

variable "database_names" {
  description = "Application databases to create with UTF8 encoding and en_US.UTF8 collation. Removing a name destroys that database."
  type        = set(string)
  validation {
    condition     = length(var.database_names) > 0 && alltrue([for name in var.database_names : can(regex("^[a-z][a-z0-9_]{0,62}$", name)) && !contains(["postgres", "template0", "template1"], name)])
    error_message = "Provide at least one non-system database name: lowercase letter followed by up to 62 lowercase letters, digits or underscores."
  }
}

variable "iam_identities" {
  description = "Identity email => USER or SERVICE_ACCOUNT. Grants project-level Cloud SQL Client and Instance User and creates an instance-local IAM database user. Service account emails must include .gserviceaccount.com; the database username is derived automatically. SQL grants remain DBA-managed."
  type        = map(string)
  validation {
    condition = length(var.iam_identities) > 0 && alltrue([
      for email, kind in var.iam_identities :
      contains(["USER", "SERVICE_ACCOUNT"], kind) && can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", email)) && lower(email) == email &&
      (kind == "SERVICE_ACCOUNT" ? endswith(email, ".gserviceaccount.com") : !endswith(email, ".gserviceaccount.com"))
    ])
    error_message = "Supply at least one lowercase identity email mapped to USER or SERVICE_ACCOUNT; service accounts must use their full .gserviceaccount.com email."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL flags. IAM authentication cannot be overridden. Confirm flag/version compatibility and restart implications before changing."
  type        = map(string)
  default     = {}
  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "IAM database authentication is mandatory and cannot be overridden."
  }
}

variable "labels" {
  description = "Additional Google Cloud labels."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protect against deletion through both OpenTofu and the Cloud SQL API. Disable and apply deliberately before a destroy."
  type        = bool
  default     = true
}
