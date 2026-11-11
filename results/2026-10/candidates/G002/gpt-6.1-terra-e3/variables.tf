variable "project_id" {
  description = "Project in which to create the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the instance, in the same region as its clients."
  type        = string
}

variable "instance_name" {
  description = "Cloud SQL instance name; must be unique in the project."
  type        = string
}

variable "private_network" {
  description = "Full self link or resource name of the existing VPC with private services access, e.g. projects/NETWORK_PROJECT/global/networks/apps-dev."
  type        = string
}

variable "tier" {
  description = "Cloud SQL machine tier selected by the DBA, e.g. db-custom-2-7680."
  type        = string
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version."
  type        = string
  default     = "POSTGRES_16"
  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version such as POSTGRES_16."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD capacity in GiB; Cloud SQL may increase it automatically."
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be a whole number of at least 10 GiB."
  }
}

variable "database_flags" {
  description = "Additional PostgreSQL flags and their string values. IAM authentication is always enabled by the module."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for name in keys(var.database_flags) : lower(name) != "cloudsql.iam_authentication"])
    error_message = "cloudsql.iam_authentication is managed by the module and cannot be overridden."
  }
}

variable "labels" {
  description = "Cloud SQL user labels for ownership and cost allocation."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "Names of application databases to create. The default postgres database exists independently."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "IAM database users, keyed by their Cloud SQL PostgreSQL username. Use CLOUD_IAM_USER for a user email, or CLOUD_IAM_SERVICE_ACCOUNT for a service account email with the .gserviceaccount.com suffix removed. Grant login/connect IAM permissions separately."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for t in values(var.iam_users) : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], t)])
    error_message = "Each IAM user type must be CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT."
  }
}
