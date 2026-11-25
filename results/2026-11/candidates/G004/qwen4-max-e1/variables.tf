# ---------------------------------------------------------------------------
# Service-specific inputs (the only things platform engineers must decide).
# Everything else has a production-grade default owned by this module.
# ---------------------------------------------------------------------------

variable "service" {
  description = "Name of the service that owns this database (e.g. \"checkout\"). Used to name every resource."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.service))
    error_message = "service must be lowercase alphanumeric with hyphens, 3-30 characters, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name. Selects the network team's VPC (apps-<environment>) in both regions."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be one of: staging, prod."
  }
}

variable "database_name" {
  description = "Initial database created in the cluster. Defaults to the service name with hyphen replaced by underscore."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only letters, digits and underscores (max 63 chars)."
  }
}

variable "primary_region" {
  description = "AWS region hosting the primary (writer) cluster. Must be a US region where the service runs on EKS."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-", var.primary_region))
    error_message = "primary_region must be a US region (us-*)."
  }
}

variable "secondary_region" {
  description = "AWS region hosting the disaster-recovery (secondary) cluster. Must differ from primary_region."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-", var.secondary_region))
    error_message = "secondary_region must be a US region (us-*)."
  }
}

variable "vpc_name" {
  description = "Name tag of the network team's VPC in each region. Defaults to apps-<environment>."
  type        = string
  default     = null
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (major.minor). Kept identical in both regions by the global cluster."
  type        = string
  default     = "16.4"

  validation {
    condition     = can(regex("^1[5-9]\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be a supported Aurora PostgreSQL major.minor version (15+)."
  }
}

variable "instance_class" {
  description = "DB instance class for all instances in both regions (memory-optimized for production PostgreSQL)."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Instances in the primary cluster: one writer plus readers. Minimum 2 so an instance failure never takes the service down."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 2 and 15 (writer + at least one reader for in-region HA)."
  }
}

variable "secondary_instance_count" {
  description = "Read-serving instances in the DR region. At least 1 so the region can take traffic immediately after failover."
  type        = number
  default     = 1

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15."
  }
}

variable "master_username" {
  description = "Master (break-glass) username. Its password is generated and rotated by RDS into Secrets Manager; day-to-day access uses IAM authentication."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = !contains(["rdsadmin", "postgres", "admin", "root"], var.master_username)
    error_message = "master_username must not be a reserved name (rdsadmin, postgres, admin, root)."
  }
}

variable "port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}

variable "iam_database_users" {
  description = "PostgreSQL users the service's EKS IAM roles may connect as (created with rds_iam grant). The module emits a least-privilege rds-db:connect policy for these users."
  type        = list(string)
  default     = ["app"]

  validation {
    condition     = length(var.iam_database_users) > 0
    error_message = "iam_database_users must contain at least one database user."
  }
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention. 731 days (2 years) keeps forensic history for customer/payment data incidents; 7 is the free tier."
  type        = number
  default     = 731

  validation {
    condition     = var.performance_insights_retention_days == 7 || var.performance_insights_retention_days == 731 || (var.performance_insights_retention_days >= 31 && var.performance_insights_retention_days <= 731 && var.performance_insights_retention_days % 31 == 0)
    error_message = "performance_insights_retention_days must be 7, 731, or a multiple of 31 between 31 and 731."
  }
}

variable "alarm_email" {
  description = "Optional email address subscribed to database alert topics in both regions."
  type        = string
  default     = null
}

variable "apply_immediately" {
  description = "Apply instance/cluster modifications immediately instead of in the maintenance window. Keep false for production."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to every resource (Service/Environment/ManagedBy are set by the module)."
  type        = map(string)
  default     = {}
}
