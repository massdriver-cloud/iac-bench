variable "service_name" {
  description = "Short, unique service name used in database and AWS resource identifiers."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,25}$", var.service_name))
    error_message = "service_name must be 2-26 lowercase letters, digits, or hyphens and start with a letter."
  }
}

variable "environment" {
  description = "Environment and VPC Name tag to select (apps-staging or apps-prod)."
  type        = string

  validation {
    condition     = contains(["apps-staging", "apps-prod"], var.environment)
    error_message = "environment must be apps-staging or apps-prod."
  }
}

variable "primary_region" {
  description = "AWS region hosting the writable Aurora Global Database primary."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Distinct US AWS region hosting the Aurora Global Database DR secondary."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "primary_region and secondary_region must differ."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must begin with a letter and contain only letters, digits, and underscores (maximum 63 characters)."
  }
}

variable "master_username" {
  description = "Managed-secret master account name; do not use this account for application traffic."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.master_username)) && lower(var.master_username) != "postgres"
    error_message = "master_username must be a valid PostgreSQL identifier and cannot be postgres."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version, pinned to avoid unreviewed major upgrades."
  type        = string
  default     = "16.6"
}

variable "parameter_group_family" {
  description = "Aurora PostgreSQL parameter group family, matching engine_version."
  type        = string
  default     = "aurora-postgresql16"
}

variable "instances_per_region" {
  description = "Aurora Serverless v2 instances in each region; at least two for in-region failover."
  type        = number
  default     = 2

  validation {
    condition     = var.instances_per_region >= 2 && var.instances_per_region == floor(var.instances_per_region)
    error_message = "instances_per_region must be an integer of at least 2."
  }
}

variable "serverless_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity per instance, in ACUs."
  type        = number
  default     = 2

  validation {
    condition     = var.serverless_min_capacity >= 0.5 && var.serverless_min_capacity <= 256
    error_message = "serverless_min_capacity must be between 0.5 and 256 ACUs."
  }
}

variable "serverless_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity per instance, in ACUs."
  type        = number
  default     = 16

  validation {
    condition     = var.serverless_max_capacity >= var.serverless_min_capacity && var.serverless_max_capacity <= 256
    error_message = "serverless_max_capacity must be at least serverless_min_capacity and no more than 256 ACUs."
  }
}

variable "backup_retention_days" {
  description = "Automated backup retention for point-in-time recovery."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "backup_window" {
  description = "Daily UTC backup window, in hh:mm-hh:mm format."
  type        = string
  default     = "03:00-03:30"
}

variable "maintenance_window" {
  description = "Weekly UTC maintenance window, in ddd:hh:mm-ddd:hh:mm format."
  type        = string
  default     = "sun:04:00-sun:04:30"
}

variable "log_retention_days" {
  description = "CloudWatch PostgreSQL log retention in days."
  type        = number
  default     = 90
}

variable "primary_eks_security_group_ids" {
  description = "EKS node/pod security groups allowed to connect to PostgreSQL in the primary VPC. Empty means no inbound access."
  type        = list(string)
  default     = []
}

variable "secondary_eks_security_group_ids" {
  description = "EKS node/pod security groups allowed to connect to PostgreSQL in the secondary VPC. Empty means no inbound access."
  type        = list(string)
  default     = []
}

variable "iam_db_user_roles" {
  description = "Optional map of PostgreSQL IAM-auth database usernames to IAM role names granted rds-db:connect in both regions."
  type        = map(list(string))
  default     = {}
}

variable "tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default     = {}
}
