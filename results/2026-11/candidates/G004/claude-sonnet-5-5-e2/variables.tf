variable "name" {
  description = "Service name this database belongs to (lowercase letters, digits, hyphens). Used in all resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 chars, lowercase alphanumeric/hyphens, start with a letter, not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment; selects the network team's VPC (apps-staging or apps-prod) in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "primary_client_security_group_ids" {
  description = "Security groups (in the primary region's VPC) allowed to connect to PostgreSQL, e.g. the EKS node/pod security group."
  type        = list(string)

  validation {
    condition     = length(var.primary_client_security_group_ids) > 0
    error_message = "Provide at least one client security group, otherwise nothing can reach the database."
  }
}

variable "secondary_client_security_group_ids" {
  description = "Security groups (in the secondary region's VPC) allowed to connect to PostgreSQL. Needed so services can reach the database after a regional failover."
  type        = list(string)

  validation {
    condition     = length(var.secondary_client_security_group_ids) > 0
    error_message = "Provide at least one client security group, otherwise nothing can reach the database after failover."
  }
}

variable "primary_region" {
  description = "Region initially hosting the writer."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Region hosting the cross-region Aurora Global Database replica, ready for failover."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must differ from primary_region."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (must support Global Database in both regions). Minor upgrades are deliberate, not automatic, so both regions stay in lockstep."
  type        = string
  default     = "16.6"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must look like \"16.6\"."
  }
}

variable "instance_class" {
  description = "Instance class for all instances. Must be a Global Database-capable class (not burstable db.t*), and secondary instances should match the primary so failover keeps capacity."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = !startswith(var.instance_class, "db.t")
    error_message = "Burstable classes are unsuitable for production and are not supported for Global Database."
  }
}

variable "primary_instance_count" {
  description = "Instances in the primary cluster (1 writer + readers). Minimum 2 so an instance/AZ failure fails over within the region."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2
    error_message = "Use at least 2 instances in the primary region for Multi-AZ failover."
  }
}

variable "secondary_instance_count" {
  description = "Instances in the secondary cluster. Minimum 2 so that, once promoted, it is itself Multi-AZ; at least one running instance is also what makes regional failover take minutes."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 2
    error_message = "Use at least 2 instances in the secondary region."
  }
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master username. Its password is generated and held by AWS Secrets Manager (never in state or code). Applications should use IAM database authentication, which is enabled."
  type        = string
  default     = "dbadmin"
}

variable "backup_retention_days" {
  description = "Automated backup retention (days) in each region."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention (7 is free tier; or 31, 62, ... multiples of 31 up to 731)."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
