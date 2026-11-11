variable "project_id" {
  description = "Project in which to create the Cloud SQL instance. The Cloud SQL Admin API must already be enabled."
  type        = string
}

variable "region" {
  description = "Region for the Cloud SQL instance."
  type        = string
}

variable "instance_name" {
  description = "Cloud SQL instance ID, unique within the project."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,97}[a-z0-9]$", var.instance_name))
    error_message = "instance_name must start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits and hyphens (2-98 characters)."
  }
}

variable "private_network" {
  description = "Full self-link or projects/HOST_PROJECT/global/networks/NETWORK path of the existing custom VPC with private services access already configured. Shared VPC host projects are supported."
  type        = string
  validation {
    condition     = can(regex("^(https://www.googleapis.com/compute/v1/)?projects/[^/]+/global/networks/[^/]+$", var.private_network))
    error_message = "private_network must be a VPC self-link or projects/PROJECT/global/networks/NETWORK path."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier sized by the DBA, for example db-custom-2-7680."
  type        = string
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL major version. Changing this may trigger an upgrade or replacement; review the plan."
  type        = string
  default     = "POSTGRES_16"
  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version such as POSTGRES_16."
  }
}

variable "availability_type" {
  description = "REGIONAL provides high availability; ZONAL is appropriate when HA is not required."
  type        = string
  default     = "REGIONAL"
  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "availability_type must be REGIONAL or ZONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD size in GB. Storage can grow automatically and cannot be reduced in place."
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 10 && floor(var.disk_size_gb) == var.disk_size_gb
    error_message = "disk_size_gb must be an integer of at least 10."
  }
}

variable "backup_start_time" {
  description = "Start of the daily automated backup window in UTC (HH:MM)."
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a UTC time in HH:MM format."
  }
}

variable "maintenance_day" {
  description = "Preferred maintenance day, Monday=1 through Sunday=7."
  type        = number
  default     = 7
  validation {
    condition     = var.maintenance_day >= 1 && var.maintenance_day <= 7 && floor(var.maintenance_day) == var.maintenance_day
    error_message = "maintenance_day must be an integer from 1 through 7."
  }
}

variable "maintenance_hour" {
  description = "Preferred maintenance start hour in UTC (0-23)."
  type        = number
  default     = 4
  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23 && floor(var.maintenance_hour) == var.maintenance_hour
    error_message = "maintenance_hour must be an integer from 0 through 23."
  }
}

variable "databases" {
  description = "Database names to create on the instance. Database-level grants remain the DBA's responsibility."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "IAM identities to create as Cloud SQL database users. Map keys are stable resource identifiers; email is the complete Google user or service account email. type is CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT. For service accounts the Cloud SQL username is derived by removing .gserviceaccount.com."
  type = map(object({
    email = string
    type  = string
  }))
  default = {}
  validation {
    condition = alltrue([
      for user in values(var.iam_users) : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT"], user.type) && (
        user.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", user.email)) : can(regex("^[^@]+@[^@]+$", user.email))
      )
    ])
    error_message = "Each identity must have a valid email and type CLOUD_IAM_USER or CLOUD_IAM_SERVICE_ACCOUNT; service account emails must end in .iam.gserviceaccount.com."
  }
}

variable "labels" {
  description = "Labels for the Cloud SQL instance."
  type        = map(string)
  default     = {}
}
