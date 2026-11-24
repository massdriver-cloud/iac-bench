variable "service_name" {
  description = "Name of the customer-facing service that owns this database (e.g., 'checkout', 'payments'). Lowercase alphanumeric and hyphens only."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-24 characters, start with a lowercase letter, end with lowercase alphanumeric, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment matching the network team's VPCs ('apps-staging' or 'apps-prod')."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod'."
  }
}

variable "database_name" {
  description = "Name of the initial PostgreSQL database created inside the cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid lowercase PostgreSQL identifier (1-63 chars, starting with a letter or underscore, containing only lowercase letters, digits, and underscores)."
  }
}

variable "primary_region" {
  description = "Primary US AWS region hosting the active writer Aurora cluster."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-[a-z]+-[0-9]+$", var.primary_region))
    error_message = "primary_region must be a valid US AWS region (e.g., us-east-1, us-west-2)."
  }
}

variable "secondary_region" {
  description = "Secondary US AWS region hosting the warm standby Aurora cluster for regional failover."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-[a-z]+-[0-9]+$", var.secondary_region))
    error_message = "secondary_region must be a valid US AWS region (e.g., us-east-1, us-west-2)."
  }
}

variable "engine_version" {
  description = "Pinned Aurora PostgreSQL engine version deployed in both regions (pinned by default to avoid unexpected upgrades)."
  type        = string
  default     = "17.9"
}

variable "instance_class" {
  description = "RDS instance class for cluster instances in both regions."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Number of Aurora instances in the primary region (minimum 2 recommended for Multi-AZ HA)."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of Aurora instances in the secondary region (2 recommended so the region retains Multi-AZ HA immediately after failover)."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15."
  }
}

variable "port" {
  description = "TCP port on which PostgreSQL accepts connections."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "port must be a non-privileged TCP port between 1024 and 65535."
  }
}

variable "master_username" {
  description = "Master administrator username for break-glass access (password is automatically managed and rotated by AWS Secrets Manager)."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username)) && !contains(["rdsadmin", "root"], lower(var.master_username))
    error_message = "master_username must be a valid PostgreSQL identifier and not a reserved AWS RDS username."
  }
}

variable "iam_database_users" {
  description = "List of PostgreSQL database usernames allowed to authenticate via IAM (rds-db:connect). Defaults to [<service_name_underscore>_app] when empty."
  type        = list(string)
  default     = []
}

variable "eks_iam_role_names" {
  description = "Optional list of existing EKS service IAM role names to attach the rds-db:connect policy to."
  type        = list(string)
  default     = []
}

variable "primary_allowed_security_group_ids" {
  description = "Security group IDs in the primary region (e.g., EKS worker/pod security groups) allowed to connect to PostgreSQL."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "Security group IDs in the secondary region (e.g., EKS worker/pod security groups) allowed to connect to PostgreSQL."
  type        = list(string)
  default     = []
}

variable "primary_allowed_cidr_blocks" {
  description = "Optional private CIDR blocks in the primary region allowed to connect to PostgreSQL. Public (0.0.0.0/0) CIDRs are forbidden."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.primary_allowed_cidr_blocks, "0.0.0.0/0") && !contains(var.primary_allowed_cidr_blocks, "::/0")
    error_message = "Wildcard CIDR blocks (0.0.0.0/0 or ::/0) are not permitted for production payment/customer databases."
  }
}

variable "secondary_allowed_cidr_blocks" {
  description = "Optional private CIDR blocks in the secondary region allowed to connect to PostgreSQL. Public (0.0.0.0/0) CIDRs are forbidden."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.secondary_allowed_cidr_blocks, "0.0.0.0/0") && !contains(var.secondary_allowed_cidr_blocks, "::/0")
    error_message = "Wildcard CIDR blocks (0.0.0.0/0 or ::/0) are not permitted for production payment/customer databases."
  }
}

variable "backup_retention_period" {
  description = "Number of days to retain automated Aurora backups (7-35). Defaults to 35 days for payment and customer data."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 7 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC time window during which automated backups may run (must not overlap with preferred_maintenance_window)."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC time window during which RDS maintenance may occur."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the global cluster and regional clusters."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip final DB cluster snapshot on deletion. Should remain false in production."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Whether cluster/instance modifications are applied immediately or during the maintenance window."
  type        = bool
  default     = false
}

variable "enable_global_write_forwarding" {
  description = "Allow secondary region read replicas to forward write queries to the primary region."
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "Retention period in days for Performance Insights data (7, 731, or multiples of 31 between 31 and 731)."
  type        = number
  default     = 93

  validation {
    condition     = var.performance_insights_retention_period == 7 || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 731 && var.performance_insights_retention_period % 31 == 0) || var.performance_insights_retention_period == 731
    error_message = "performance_insights_retention_period must be 7, 731, or a multiple of 31 between 31 and 731."
  }
}

variable "monitoring_interval" {
  description = "Interval in seconds for RDS Enhanced Monitoring OS metrics (0, 1, 5, 10, 15, 30, or 60)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, or 60."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days for PostgreSQL and pgAudit logs."
  type        = number
  default     = 365

  validation {
    condition     = var.log_retention_days >= 90
    error_message = "log_retention_days must be at least 90 days for customer and payment audit compliance."
  }
}

variable "pgaudit_log" {
  description = "Comma-separated classes of statements logged by pgAudit (e.g., 'ddl,role,write' or 'all')."
  type        = string
  default     = "ddl,role,write"
}

variable "slow_query_threshold_ms" {
  description = "Log queries running longer than this duration in milliseconds."
  type        = number
  default     = 1000
}

variable "idle_in_transaction_session_timeout_ms" {
  description = "Terminate sessions idle inside an open transaction after this duration in milliseconds."
  type        = number
  default     = 300000
}

variable "global_rpo_lag_alarm_threshold_ms" {
  description = "CloudWatch alarm threshold in milliseconds for Aurora Global Database RPO lag across regions."
  type        = number
  default     = 5000
}

variable "primary_alarm_sns_topic_arns" {
  description = "Optional SNS topic ARNs in the primary region to notify when database alarms trigger."
  type        = list(string)
  default     = []
}

variable "secondary_alarm_sns_topic_arns" {
  description = "Optional SNS topic ARNs in the secondary region to notify when database or RPO lag alarms trigger."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional resource tags merged onto all taggable resources."
  type        = map(string)
  default     = {}
}
