variable "service_name" {
  description = "Short name of the owning service, e.g. \"checkout\". Used in every resource name and tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,29}(-[a-z0-9]+)*$", var.service_name)) && length(var.service_name) <= 30
    error_message = "service_name must be 2-30 chars, lowercase letters, digits and single hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment this database serves. Selects the apps-<environment> VPC in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "primary_region" {
  description = "AWS region that hosts the writer cluster at steady state, e.g. \"us-east-1\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.primary_region))
    error_message = "primary_region must be an AWS region name such as us-east-1."
  }
}

variable "secondary_region" {
  description = "AWS region that hosts the cross-region read-only replica cluster, promoted during a regional failover. Must differ from primary_region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.secondary_region))
    error_message = "secondary_region must be an AWS region name such as us-west-2."
  }
}

variable "database_name" {
  description = "Name of the initial database created in the cluster."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a lowercase letter and contain only lowercase letters, digits and underscores."
  }
}

variable "master_username" {
  description = "Master (admin) username. The password is generated and stored in Secrets Manager; it is never in state as a plain variable."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,15}$", var.master_username)) && var.master_username != "postgres"
    error_message = "master_username must be 1-16 chars, start with a letter, and must not be \"postgres\"."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (major.minor). Must be supported for Aurora Global Database in both regions."
  type        = string
  default     = "16.6"

  validation {
    condition     = can(regex("^1[5-7]\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be an Aurora PostgreSQL 15, 16 or 17 version such as 16.6."
  }
}

variable "instance_class" {
  description = "Instance class for every writer and reader instance in both regions. Must be a Global Database-capable class."
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = "Number of DB instances per region. Minimum 2 so each region keeps a reader in a different AZ for in-region failover."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 2 && var.instance_count <= 15
    error_message = "instance_count must be between 2 and 15."
  }
}

variable "backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "backup_window" {
  description = "Daily UTC window for automated backups. Must not overlap maintenance_window."
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly UTC window for maintenance. Must not overlap backup_window."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Blocks deletion of the clusters and global cluster. Leave true for production; set false only to tear down a disposable environment."
  type        = bool
  default     = true
}

variable "iam_database_users" {
  description = "Database users that authenticate with IAM (rds-db:connect). Each must be created in PostgreSQL and granted rds_iam; see README."
  type        = list(string)
  default     = ["app"]

  validation {
    condition     = length(var.iam_database_users) > 0 && alltrue([for u in var.iam_database_users : can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", u))])
    error_message = "iam_database_users must contain at least one valid PostgreSQL role name."
  }
}

variable "application_role_names" {
  description = "Names of existing IAM roles (e.g. the EKS IRSA roles for the service) that get rds-db:connect for iam_database_users. Empty means the policy is created but not attached."
  type        = list(string)
  default     = []
}

variable "additional_ingress_cidrs" {
  description = "Extra CIDRs allowed to reach PostgreSQL on 5432 in both regions, in addition to each regional VPC CIDR. Use only for CIDRs that are not inside the VPC (e.g. VPN ranges for admin access)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to every resource via provider default_tags."
  type        = map(string)
  default     = {}
}
