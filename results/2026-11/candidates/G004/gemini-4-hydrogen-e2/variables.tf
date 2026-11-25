variable "service_name" {
  description = "Lowercase identifier of the customer-facing service that owns this database (e.g. \"checkout\", \"payments\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-30 characters, lowercase alphanumeric and hyphens, starting with a letter and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Target deployment environment matching the network team's VPCs (apps-staging or apps-prod)."
  type        = string

  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "environment must be either \"prod\" or \"staging\"."
  }
}

variable "primary_region" {
  description = "Primary US AWS region hosting the active Aurora PostgreSQL writer cluster."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.primary_region))
    error_message = "primary_region must be a US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "secondary_region" {
  description = "Secondary US AWS region hosting the warm Aurora Global Database standby cluster."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.secondary_region))
    error_message = "secondary_region must be a US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name created in the cluster. Defaults to service_name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier (1-63 alphanumeric or underscore characters, not starting with a digit)."
  }
}

variable "master_username" {
  description = "Master superuser name stored in AWS Secrets Manager for break-glass DBA bootstrap."
  type        = string
  default     = "aurora_admin"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must be a valid PostgreSQL role identifier."
  }
}

variable "iam_db_users" {
  description = "PostgreSQL role names authorized for EKS IAM database authentication (rds-db:connect). Defaults to [database_name] when empty."
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version deployed across both regions."
  type        = string
  default     = "16.15"
}

variable "instance_class" {
  description = "RDS instance class for cluster nodes. Burstable db.t* classes are disallowed because Aurora Global Database requires memory-optimized instances."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.(r|x|z)[0-9a-z]+\\.", var.instance_class))
    error_message = "instance_class must be a memory-optimized RDS class supported by Aurora Global Database (e.g. db.r6g.large, db.r7g.large)."
  }
}

variable "primary_instance_count" {
  description = "Number of Aurora instances in the primary region. Defaults to 2 (Multi-AZ writer + reader) in prod, 1 in staging."
  type        = number
  default     = null

  validation {
    condition     = var.primary_instance_count == null || (var.primary_instance_count >= 1 && var.primary_instance_count <= 15)
    error_message = "primary_instance_count must be between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of warm Aurora instances in the secondary region for fast regional failover. Defaults to 2 in prod, 1 in staging."
  type        = number
  default     = null

  validation {
    condition     = var.secondary_instance_count == null || (var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15)
    error_message = "secondary_instance_count must be between 1 and 15 (at least 1 warm instance is required for minute-scale regional failover)."
  }
}

variable "backup_retention_period" {
  description = "Automated backup retention period in days (1-35). Defaults to 35 in prod and 14 in staging."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_period == null || (var.backup_retention_period >= 7 && var.backup_retention_period <= 35)
    error_message = "backup_retention_period must be between 7 and 35 days for production customer/payment data."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC backup window (must not overlap preferred_maintenance_window)."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC maintenance window."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Protect global cluster and regional clusters from accidental deletion."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip final snapshot on cluster destruction. Disabled by default to prevent data loss."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply cluster/instance modifications immediately rather than during the maintenance window."
  type        = bool
  default     = false
}

variable "enable_global_write_forwarding" {
  description = "Enable Aurora Global Database write forwarding from secondary reader nodes to the primary writer."
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring OS metrics collection interval in seconds (0, 1, 5, 10, 15, 30, 60)."
  type        = number
  default     = 15

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be 1, 5, 10, 15, 30, or 60 seconds for production observability."
  }
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days (7, or multiples of 31 up to 731). Defaults to 93 in prod and 7 in staging."
  type        = number
  default     = null

  validation {
    condition = var.performance_insights_retention_period == null || (
      var.performance_insights_retention_period == 7 ||
      (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 731 && var.performance_insights_retention_period % 31 == 0)
    )
    error_message = "performance_insights_retention_period must be 7 or a multiple of 31 between 31 and 731."
  }
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention period in days for PostgreSQL audit/error logs. Defaults to 365 in prod and 90 in staging."
  type        = number
  default     = null
}

variable "pgaudit_log" {
  description = "pgAudit log classes (e.g. \"ddl,role\" or \"ddl,role,write\")."
  type        = string
  default     = "ddl,role"
}

variable "slow_query_log_threshold_ms" {
  description = "Minimum query execution time in milliseconds to log (log_min_duration_statement)."
  type        = string
  default     = "1000"
}

variable "statement_timeout_ms" {
  description = "Maximum allowed statement duration in milliseconds before cancellation."
  type        = string
  default     = "30000"
}

variable "idle_in_transaction_session_timeout_ms" {
  description = "Maximum allowed idle time in milliseconds inside an open transaction before termination."
  type        = string
  default     = "300000"
}

variable "extra_cluster_parameters" {
  description = "Additional Aurora PostgreSQL cluster parameters (map of name => { value, apply_method })."
  type = map(object({
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = {}
}

variable "extra_db_parameters" {
  description = "Additional Aurora PostgreSQL DB instance parameters (map of name => { value, apply_method })."
  type = map(object({
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = {}
}

variable "primary_allowed_security_group_ids" {
  description = "Security group IDs (e.g. EKS node/pod security groups) permitted to connect to PostgreSQL (5432) in the primary region."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "Security group IDs (e.g. EKS node/pod security groups) permitted to connect to PostgreSQL (5432) in the secondary region."
  type        = list(string)
  default     = []
}

variable "primary_allowed_cidr_blocks" {
  description = "CIDR blocks permitted to connect to PostgreSQL (5432) in the primary region."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_cidr_blocks" {
  description = "CIDR blocks permitted to connect to PostgreSQL (5432) in the secondary region."
  type        = list(string)
  default     = []
}

variable "primary_alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN for primary region alarms. If null, a KMS-encrypted SNS topic is created."
  type        = string
  default     = null
}

variable "secondary_alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN for secondary region alarms. If null, a KMS-encrypted SNS topic is created."
  type        = string
  default     = null
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Threshold in milliseconds for the AuroraGlobalDBReplicationLag CloudWatch alarm (guards the few-second RPO target)."
  type        = number
  default     = 2000
}

variable "cpu_alarm_threshold_percent" {
  description = "CPU utilization percentage threshold for CloudWatch alarms."
  type        = number
  default     = 80
}

variable "freeable_memory_alarm_threshold_bytes" {
  description = "Minimum freeable memory threshold in bytes before alarming."
  type        = number
  default     = 536870912
}

variable "database_connections_alarm_threshold" {
  description = "Database connections threshold for CloudWatch alarms."
  type        = number
  default     = 500
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period in days before KMS key deletion (7-30)."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "Additional tags merged onto all taggable resources."
  type        = map(string)
  default     = {}
}
