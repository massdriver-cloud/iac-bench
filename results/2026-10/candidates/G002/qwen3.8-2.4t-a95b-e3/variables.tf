# -----------------------------------------------------------------------------
# Required inputs: the smallest decisions a DBA must make per instance.
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = <<-EOT
    Short service/database identifier, e.g. "orders" or "billing". The module
    applies the standard naming convention and creates the instance as
    "<environment>-<name>" (e.g. "prod-orders"), so pass only the workload
    identifier — no environment prefix.
  EOT

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,48}[a-z0-9])?$", var.name))
    error_message = "name must be 1-50 characters, start with a lowercase letter, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment. Selects the environment's standard VPC network (apps-<environment>); private services access is pre-provisioned there by the network team."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# -----------------------------------------------------------------------------
# Optional inputs: genuine DBA decisions, with sensible defaults.
# -----------------------------------------------------------------------------

variable "project" {
  type        = string
  default     = null
  description = "GCP project to create the instance in. Defaults to the project of the ambient credentials when null."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "GCP region for the instance."
}

variable "database_version" {
  type        = string
  default     = "POSTGRES_16"
  description = "PostgreSQL major version."

  validation {
    condition     = contains(["POSTGRES_12", "POSTGRES_13", "POSTGRES_14", "POSTGRES_15", "POSTGRES_16", "POSTGRES_17", "POSTGRES_18"], var.database_version)
    error_message = "database_version must be a supported PostgreSQL version, e.g. POSTGRES_16."
  }
}

variable "tier" {
  type        = string
  default     = "db-custom-1-3840"
  description = "Machine tier, e.g. db-custom-2-8192 (2 vCPU / 8 GiB). DBA-sized per workload."

  validation {
    condition     = startswith(var.tier, "db-")
    error_message = "tier must be a Cloud SQL machine type starting with \"db-\"."
  }
}

variable "availability_type" {
  type        = string
  default     = "ZONAL"
  description = "ZONAL (single zone) or REGIONAL (standby in a second zone). Consider REGIONAL for production workloads."

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "storage_gb" {
  type        = number
  default     = 20
  description = "Initial storage size in GiB. Autogrowth is always enabled."

  validation {
    condition     = var.storage_gb >= 10
    error_message = "storage_gb must be at least 10."
  }
}

variable "disk_type" {
  type        = string
  default     = "PD_SSD"
  description = "Storage type: PD_SSD, PD_HDD or HYPERDISK_BALANCED."

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.disk_type)
    error_message = "disk_type must be PD_SSD, PD_HDD or HYPERDISK_BALANCED."
  }
}

variable "database_flags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    PostgreSQL server flags (e.g. max_connections, work_mem). Note:
    cloudsql.iam_authentication is managed by the module and cannot be
    disabled per instance.
  EOT
}

variable "databases" {
  type        = list(string)
  default     = ["app"]
  description = "Application databases to create on the instance."
}

variable "iam_users" {
  type        = set(string)
  default     = []
  description = "Email addresses of Google users/groups that may authenticate to the instance via IAM."
}

variable "iam_service_accounts" {
  type        = set(string)
  default     = []
  description = "Email addresses of service accounts (GKE workloads, Compute Engine VMs, jobs) that may authenticate to the instance via IAM."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Extra labels to apply. The module always adds environment and managed_by."
}

variable "backup_retention_days" {
  type        = number
  default     = 7
  description = "Number of automated backups to retain (1-365). Backups and point-in-time recovery are always enabled."

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "backup_retention_days must be between 1 and 365."
  }
}

variable "backup_start_hour" {
  type        = number
  default     = 3
  description = "Hour of day (0-23, UTC) at which the backup window starts."

  validation {
    condition     = var.backup_start_hour >= 0 && var.backup_start_hour <= 23
    error_message = "backup_start_hour must be between 0 and 23."
  }
}

variable "maintenance_day" {
  type        = number
  default     = 7
  description = "Day of week (1 = Monday ... 7 = Sunday) for the self-service maintenance window."

  validation {
    condition     = var.maintenance_day >= 1 && var.maintenance_day <= 7
    error_message = "maintenance_day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_hour" {
  type        = number
  default     = 4
  description = "Hour of day (0-23, UTC) for the maintenance window."

  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23
    error_message = "maintenance_hour must be between 0 and 23."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Guardrail against accidental destruction of a database. Defaults to true; set to false only for throwaway instances (and remember to set it back before promoting them)."
}

variable "network" {
  type        = string
  default     = null
  description = <<-EOT
    Escape hatch only: full self link of a VPC network to use instead of the
    environment's standard network. The standard path (leave this null) places
    the instance in apps-<environment>.
  EOT
}
