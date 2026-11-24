variable "name" {
  description = "Short service name used in resource names (for example, checkout). Must start with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 characters and contain only lowercase letters, numbers, and hyphens; it must start with a letter and end with a letter or number."
  }
}

variable "environment" {
  description = "Network environment. This selects the apps-staging or apps-prod VPC in both regions."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either staging or prod."
  }
}

variable "primary_region" {
  description = "US region containing the initial Aurora writer."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-(east|west)-[1-9]$", var.primary_region))
    error_message = "primary_region must be a commercial US AWS region."
  }
}

variable "secondary_region" {
  description = "US region containing the always-running disaster-recovery cluster."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-(east|west)-[1-9]$", var.secondary_region))
    error_message = "secondary_region must be a commercial US AWS region."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name. If null, the service name is used with hyphens changed to underscores."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.database_name == null || can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier of at most 63 characters."
  }
}

variable "master_username" {
  description = "Aurora master username. Its password is generated and managed by RDS in Secrets Manager."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.master_username)) && !contains(["admin", "postgres", "root"], lower(var.master_username))
    error_message = "master_username must be a valid non-reserved PostgreSQL identifier."
  }
}

variable "iam_database_user_name" {
  description = "PostgreSQL role that applications use with IAM database authentication. Create this role and grant it rds_iam after provisioning."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.iam_database_user_name))
    error_message = "iam_database_user_name must be a valid PostgreSQL identifier of at most 63 characters."
  }
}

variable "application_iam_role_names" {
  description = "Names of same-account EKS application IAM roles to which the least-privilege rds-db:connect policy is attached."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "application_security_group_ids" {
  description = "EKS application security groups allowed to reach PostgreSQL in each region. Empty lists intentionally create no application ingress."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for id in concat(var.application_security_group_ids.primary, var.application_security_group_ids.secondary) :
      can(regex("^sg-[0-9a-fA-F]{8,17}$", id))
    ])
    error_message = "Every application security group ID must be a valid sg-* identifier."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. PostgreSQL 16 or newer is required by this module's managed-RPO baseline."
  type        = string
  default     = "16.4"

  validation {
    condition = (
      can(regex("^[0-9]+\\.[0-9]+$", var.engine_version)) &&
      tonumber(split(".", var.engine_version)[0]) >= 16
    )
    error_message = "engine_version must be a major.minor Aurora PostgreSQL version with major version 16 or newer."
  }
}

variable "instance_class" {
  description = "Provisioned instance class used identically in both regions so the DR region can immediately take production load."
  type        = string
  default     = "db.r6g.large"
}

variable "instances_per_region" {
  description = "Instances in each regional cluster. At least two are required for in-region availability and failover capacity."
  type        = number
  default     = 2

  validation {
    condition     = var.instances_per_region >= 2 && var.instances_per_region <= 6 && floor(var.instances_per_region) == var.instances_per_region
    error_message = "instances_per_region must be a whole number between 2 and 6."
  }
}

variable "port" {
  description = "PostgreSQL listener port."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1024 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be a whole number between 1024 and 65535."
  }
}

variable "global_rpo_milliseconds" {
  description = "Maximum tolerated cross-region replication lag before Aurora throttles primary commits. The default enforces a five-second RPO."
  type        = number
  default     = 5000

  validation {
    condition     = var.global_rpo_milliseconds >= 1000 && var.global_rpo_milliseconds <= 10000 && floor(var.global_rpo_milliseconds) == var.global_rpo_milliseconds
    error_message = "global_rpo_milliseconds must be a whole number from 1000 through 10000."
  }
}

variable "backup_retention_period" {
  description = "Point-in-time recovery retention, in days, for the primary cluster."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period must be a whole number between 7 and 35."
  }
}

variable "log_retention_days" {
  description = "Retention for exported PostgreSQL logs in CloudWatch Logs."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention value supported by CloudWatch Logs."
  }
}

variable "operations_email_endpoints" {
  description = "Optional email addresses subscribed to both regional operations topics. Email subscriptions must be confirmed by the recipient."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the global cluster and both regional clusters."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Additional tags applied to all taggable resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
