variable "service_name" {
  description = "Service identifier (e.g., checkout, payments). Used to name Aurora clusters, KMS aliases, security groups, and IAM policies."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-30 characters, lowercase alphanumeric and hyphens, starting with a letter and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment. Maps to the network team's pre-created apps-<environment> VPC in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

variable "primary_region" {
  description = "Primary US AWS region hosting the active writer Aurora cluster."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.primary_region))
    error_message = "primary_region must be a valid commercial US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "secondary_region" {
  description = "Secondary US AWS region hosting the warm standby Aurora cluster for cross-region failover."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.secondary_region))
    error_message = "secondary_region must be a valid commercial US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name created in the primary cluster. Defaults to service_name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier (1-63 chars, letters/numbers/underscores, not starting with a digit)."
  }
}

variable "master_username" {
  description = "Master superuser name for break-glass/bootstrap access (password is auto-managed and rotated by AWS Secrets Manager)."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.master_username)) && var.master_username != "rdsadmin"
    error_message = "master_username must be a valid PostgreSQL identifier and cannot be \"rdsadmin\"."
  }
}

variable "engine_major_version" {
  description = "Aurora PostgreSQL major version. The module resolves the latest patch release available in the primary region."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["15", "16", "17"], var.engine_major_version)
    error_message = "engine_major_version must be one of \"15\", \"16\", or \"17\"."
  }
}

variable "instance_class" {
  description = "Aurora DB instance class for primary instances. Defaults to \"db.r6g.large\" in prod and \"db.serverless\" in staging. Burstable db.t* classes are unsupported by Aurora Global Databases."
  type        = string
  default     = null

  validation {
    condition     = var.instance_class == null || (var.instance_class == "db.serverless" || can(regex("^db\\.(r6g|r6i|r7g|r7i|r5|x2g)\\.", var.instance_class)))
    error_message = "instance_class must be \"db.serverless\" or a supported Global Database memory-optimized class (e.g., db.r6g.large, db.r7g.xlarge)."
  }
}

variable "secondary_instance_class" {
  description = "Aurora DB instance class for secondary region instances. Defaults to match instance_class."
  type        = string
  default     = null

  validation {
    condition     = var.secondary_instance_class == null || (var.secondary_instance_class == "db.serverless" || can(regex("^db\\.(r6g|r6i|r7g|r7i|r5|x2g)\\.", var.secondary_instance_class)))
    error_message = "secondary_instance_class must be \"db.serverless\" or a supported Global Database memory-optimized class."
  }
}

variable "primary_instance_count" {
  description = "Number of DB instances in the primary region cluster (2+ provides intra-region Multi-AZ high availability)."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be an integer >= 1."
  }
}

variable "secondary_instance_count" {
  description = "Number of warm DB instances in the secondary region cluster (must be >= 1 to meet sub-minute/few-minute regional failover RTO)."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be an integer >= 1 so the secondary cluster is warm and ready to serve immediately upon failover."
  }
}

variable "serverlessv2_min_capacity" {
  description = "Minimum Aurora Serverless v2 ACUs when using db.serverless instance class."
  type        = number
  default     = 0.5

  validation {
    condition     = var.serverlessv2_min_capacity >= 0.5 && var.serverlessv2_min_capacity <= 128
    error_message = "serverlessv2_min_capacity must be between 0.5 and 128."
  }
}

variable "serverlessv2_max_capacity" {
  description = "Maximum Aurora Serverless v2 ACUs when using db.serverless instance class."
  type        = number
  default     = 8

  validation {
    condition     = var.serverlessv2_max_capacity >= 1 && var.serverlessv2_max_capacity <= 256
    error_message = "serverlessv2_max_capacity must be between 1 and 256."
  }
}

variable "storage_type" {
  description = "Aurora cluster storage type (\"aurora\" standard or \"aurora-iopt1\" I/O-Optimized)."
  type        = string
  default     = "aurora"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be \"aurora\" or \"aurora-iopt1\"."
  }
}

variable "port" {
  description = "TCP port on which Aurora PostgreSQL listens."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "port must be between 1024 and 65535."
  }
}

variable "primary_allowed_security_group_ids" {
  description = "Security group IDs (e.g., EKS node/pod security groups) allowed to reach Aurora in the primary region."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "Security group IDs (e.g., EKS node/pod security groups) allowed to reach Aurora in the secondary region."
  type        = list(string)
  default     = []
}

variable "primary_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach Aurora in the primary region."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach Aurora in the secondary region."
  type        = list(string)
  default     = []
}

variable "allow_vpc_cidr" {
  description = "If true, permits ingress from the entire apps-<environment> VPC CIDR in each region. Disabled by default for least-privilege isolation of customer/payment data."
  type        = bool
  default     = false
}

variable "iam_auth_db_users" {
  description = "PostgreSQL database role names permitted for IAM database authentication via the generated IAM policy. Defaults to [database_name]."
  type        = list(string)
  default     = null
}

variable "eks_iam_role_names" {
  description = "Optional list of existing EKS IRSA/Pod Identity IAM role names to attach the generated rds-db:connect IAM policy to."
  type        = list(string)
  default     = []
}

variable "backup_retention_period" {
  description = "Automated backup retention period in days. Defaults to 35 in prod and 7 in staging."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_period == null || (var.backup_retention_period >= 1 && var.backup_retention_period <= 35)
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC time window for automated backups."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC maintenance window (must not overlap with preferred_backup_window)."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Protect clusters and the global database against accidental deletion. Defaults to true in prod and false in staging."
  type        = bool
  default     = null
}

variable "skip_final_snapshot" {
  description = "Skip taking a final snapshot when destroying the primary cluster. Defaults to false in prod and true in staging."
  type        = bool
  default     = null
}

variable "apply_immediately" {
  description = "Apply cluster/instance modifications immediately instead of during the maintenance window. Defaults to false in prod and true in staging."
  type        = bool
  default     = null
}

variable "auto_minor_version_upgrade" {
  description = "Enable automatic minor engine version upgrades during the maintenance window."
  type        = bool
  default     = true
}

variable "enable_global_write_forwarding" {
  description = "Enable Aurora Global Database write forwarding from secondary region to primary."
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "RDS Enhanced Monitoring collection interval in seconds (0 disables)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, or 60."
  }
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention in days (7, or a multiple of 31 up to 731). Defaults to 31 in prod and 7 in staging."
  type        = number
  default     = null

  validation {
    condition     = var.performance_insights_retention_days == null || var.performance_insights_retention_days == 7 || (var.performance_insights_retention_days >= 31 && var.performance_insights_retention_days <= 731 && var.performance_insights_retention_days % 31 == 0)
    error_message = "performance_insights_retention_days must be 7 or a multiple of 31 between 31 and 731."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days for PostgreSQL audit/query logs. Defaults to 365 in prod and 30 in staging."
  type        = number
  default     = null
}

variable "pgaudit_log" {
  description = "pgaudit.log setting controlling audited SQL statement classes."
  type        = string
  default     = "ddl,role"
}

variable "statement_timeout_ms" {
  description = "Maximum execution duration (ms) for any SQL statement before cancellation."
  type        = number
  default     = 30000
}

variable "idle_in_transaction_session_timeout_ms" {
  description = "Maximum idle time (ms) inside an open transaction before session termination."
  type        = number
  default     = 60000
}

variable "lock_timeout_ms" {
  description = "Maximum wait time (ms) to acquire a lock before failing."
  type        = number
  default     = 5000
}

variable "slow_query_threshold_ms" {
  description = "Log queries executing longer than this threshold (ms)."
  type        = number
  default     = 1000
}

variable "enable_logical_replication" {
  description = "Enable PostgreSQL logical replication (rds.logical_replication) for CDC pipelines."
  type        = bool
  default     = false
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period (days) before scheduled KMS key deletion."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}

variable "replication_lag_alarm_threshold_ms" {
  description = "CloudWatch alarm threshold (ms) for cross-region Aurora Global DB replication lag."
  type        = number
  default     = 5000
}

variable "cpu_alarm_threshold_percent" {
  description = "CloudWatch alarm threshold (%) for sustained high CPU utilization."
  type        = number
  default     = 80
}

variable "freeable_memory_alarm_threshold_bytes" {
  description = "CloudWatch alarm threshold (bytes) for low FreeableMemory on provisioned instances."
  type        = number
  default     = 1073741824
}

variable "primary_alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN in the primary region for database alarms and RDS events. If null, the module creates an encrypted SNS topic."
  type        = string
  default     = null
}

variable "secondary_alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN in the secondary region for database alarms and RDS events. If null, the module creates an encrypted SNS topic."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional resource tags merged into all created AWS resources."
  type        = map(string)
  default     = {}
}
