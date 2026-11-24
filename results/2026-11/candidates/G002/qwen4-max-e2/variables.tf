# ---------------------------------------------------------------------------
# DBA-owned decisions. These are the knobs that genuinely differ per instance;
# everything that should be uniform across the fleet is fixed in main.tf.
# ---------------------------------------------------------------------------

variable "instance_name" {
  description = "Name of the Cloud SQL instance. Must be unique within the project and follow Cloud SQL naming rules (lowercase letters, digits, hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must be 2-63 characters, start with a letter, end with a letter or digit, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Environment this instance belongs to. Selects the apps VPC (apps-dev / apps-staging / apps-prod) the instance is peered into via private services access."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Google Cloud region for the instance. Should be the region the environment's applications run in."
  type        = string
  default     = "us-central1"
}

variable "database_version" {
  description = "PostgreSQL engine version (e.g. POSTGRES_15, POSTGRES_16). Only PostgreSQL is supported by this module."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = startswith(var.database_version, "POSTGRES_")
    error_message = "database_version must be a PostgreSQL version (POSTGRES_*)."
  }
}

variable "tier" {
  description = "Machine tier for the instance (e.g. db-custom-2-7680, db-perf-optimized-N-2)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "REGIONAL for synchronous standby in a second zone (HA), ZONAL for a single zone. Production databases should stay REGIONAL."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GB. The disk auto-resizes from here; it can never shrink."
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10 GB."
  }
}

variable "disk_type" {
  description = "Data disk type. PD_SSD is the standard for database workloads."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Ceiling (GB) for disk autoresize. 0 means no limit."
  type        = number
  default     = 0
}

variable "deletion_protection" {
  description = "Protect the instance from accidental deletion (both at the API and in OpenTofu). Turn off only when deliberately decommissioning an instance."
  type        = bool
  default     = true
}

variable "databases" {
  description = "Additional databases to create on the instance. The default 'postgres' database always exists."
  type        = list(string)
  default     = []
}

variable "iam_users" {
  description = <<-EOT
    Google identities to register as IAM database users. Database access is
    audited by Google identity, so password-based users are not supported by
    this module. type is CLOUD_IAM_USER for humans/workloads with user
    credentials, or CLOUD_IAM_SERVICE_ACCOUNT for GKE/GCE service accounts.
  EOT
  type = list(object({
    email = string
    type  = string
  }))
  default = []

  validation {
    condition     = alltrue([for u in var.iam_users : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], u.type)])
    error_message = "Each iam_users entry must have type CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}

variable "user_labels" {
  description = "Extra labels to attach to the instance (e.g. owning team, application). The standard environment/managed-by/engine labels are always applied."
  type        = map(string)
  default     = {}
}
