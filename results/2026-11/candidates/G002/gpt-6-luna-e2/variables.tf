variable "project_id" {
  description = "Google Cloud project that owns the Cloud SQL instance."
  type        = string
  nullable    = false
}

variable "instance_name" {
  description = "Globally unique Cloud SQL instance name within the project."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must be 2-98 lowercase letters, digits, or hyphens, beginning with a letter and ending with a letter or digit."
  }
}

variable "region" {
  description = "Region for the Cloud SQL instance."
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Environment whose pre-existing apps-<environment> VPC has Private Services Access configured."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging, or prod."
  }
}

variable "network_project_id" {
  description = "Project containing the apps-<environment> VPC (useful for Shared VPC); defaults to project_id."
  type        = string
  default     = null
  nullable    = true
}

variable "database_name" {
  description = "Name of the application database created in the instance."
  type        = string
  nullable    = false
}

variable "tier" {
  description = "Cloud SQL machine tier selected by the DBA for this workload."
  type        = string
  nullable    = false
}

variable "database_version" {
  description = "PostgreSQL major version. DBAs may select an available supported version."
  type        = string
  default     = "POSTGRES_16"
}

variable "initial_disk_size_gb" {
  description = "Initial SSD data disk size in GB; disk autoresize is enabled."
  type        = number
  default     = 20

  validation {
    condition     = var.initial_disk_size_gb >= 10
    error_message = "initial_disk_size_gb must be at least 10 GB."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum disk autoresize size in GB; 0 means no configured upper limit."
  type        = number
  default     = 0
}

variable "deletion_protection" {
  description = "Protect the instance against accidental deletion (also enabled in Cloud SQL settings)."
  type        = bool
  default     = true
}

variable "maintenance_day" {
  description = "Preferred maintenance day, 1=Monday through 7=Sunday."
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_day >= 1 && var.maintenance_day <= 7
    error_message = "maintenance_day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_hour" {
  description = "Preferred maintenance hour in UTC, from 0 through 23."
  type        = number
  default     = 3

  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23
    error_message = "maintenance_hour must be between 0 and 23."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL flags; cloudsql.iam_authentication is managed and cannot be overridden."
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "Do not set cloudsql.iam_authentication; IAM database authentication is enforced by this module."
  }
}

variable "iam_database_users" {
  description = "Map of stable keys to IAM database users. type is CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT; database_username is the Cloud SQL IAM database username. IAM permissions are managed outside this module."
  type = map(object({
    database_username = string
    type              = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for user in values(var.iam_database_users) : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], user.type)
    ])
    error_message = "Each IAM database user's type must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}

variable "labels" {
  description = "Additional resource labels (environment and managed_by are set by the module)."
  type        = map(string)
  default     = {}
}
