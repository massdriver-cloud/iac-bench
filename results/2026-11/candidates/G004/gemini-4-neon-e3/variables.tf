# ------------------------------------------------------------------------------
# Required service-specific inputs
# ------------------------------------------------------------------------------

variable "service_name" {
  description = "Short, lowercase identifier for the customer-facing service owning this database (e.g., checkout, payments)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}[a-z0-9]$", var.service_name)) && !can(regex("--", var.service_name))
    error_message = "service_name must be 3-26 characters, start with a lowercase letter, contain only lowercase letters, numbers, and single hyphens, and not end with a hyphen."
  }
}

variable "environment" {
  description = "Target environment (staging or prod). Determines which network VPC (apps-<environment>) the clusters deploy into."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

# ------------------------------------------------------------------------------
# Multi-region topology (Aurora Global Database)
# ------------------------------------------------------------------------------

variable "primary_region" {
  description = "Primary US AWS region hosting the active writer Aurora PostgreSQL cluster."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "primary_region must be a valid US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "secondary_region" {
  description = "Secondary US AWS region hosting the warm Aurora Global Database replica cluster for rapid regional failover."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region)
    error_message = "secondary_region must be a valid US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "enable_global_write_forwarding" {
  description = "Enable Aurora Global Database write forwarding on the secondary cluster so secondary-region EKS pods can forward writes to the primary."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# Engine, sizing & high availability
# ------------------------------------------------------------------------------

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (must support Aurora Global Databases)."
  type        = string
  default     = "16.6"
}

variable "database_name" {
  description = "Initial PostgreSQL database name. Defaults to service_name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a lowercase letter and contain only lowercase letters, numbers, and underscores (max 63 chars)."
  }
}

variable "master_username" {
  description = "Master administrator username (credentials are automatically generated and rotated in AWS Secrets Manager)."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{2,62}$", var.master_username)) && !contains(["rdsadmin", "admin", "root"], var.master_username)
    error_message = "master_username must be 3-63 lowercase alphanumeric/underscore characters starting with a letter, and cannot be a reserved name (rdsadmin, admin, root)."
  }
}

variable "port" {
  description = "TCP port on which Aurora PostgreSQL listens."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port must be between 1150 and 65535."
  }
}

variable "instance_class" {
  description = "DB instance class for primary cluster nodes (Graviton memory-optimized recommended for PostgreSQL)."
  type        = string
  default     = "db.r6g.large"
}

variable "secondary_instance_class" {
  description = "Optional DB instance class for secondary cluster nodes. Defaults to matching instance_class so failover capacity matches primary."
  type        = string
  default     = null
}

variable "primary_instance_count" {
  description = "Number of DB instances in the primary region (>= 2 recommended for Multi-AZ failover)."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 16
    error_message = "primary_instance_count must be between 1 and 16."
  }
}

variable "secondary_instance_count" {
  description = "Number of warm DB instances in the secondary region (>= 2 gives immediate Multi-AZ HA after a regional failover)."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 16
    error_message = "secondary_instance_count must be between 1 and 16 so the secondary region can serve traffic immediately upon failover."
  }
}

variable "storage_type" {
  description = "Aurora storage configuration: \"aurora\" (standard) or \"aurora-iopt1\" (I/O-Optimized for I/O-intensive workloads)."
  type        = string
  default     = "aurora"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be \"aurora\" or \"aurora-iopt1\"."
  }
}

# ------------------------------------------------------------------------------
# Network access & EKS IAM authentication
# ------------------------------------------------------------------------------

variable "primary_allowed_security_group_ids" {
  description = "Security group IDs in the primary region (e.g., EKS pod/node SGs) allowed to connect to PostgreSQL."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "Security group IDs in the secondary region (e.g., EKS pod/node SGs) allowed to connect to PostgreSQL."
  type        = list(string)
  default     = []
}

variable "primary_allowed_cidr_blocks" {
  description = "Optional IPv4 CIDR blocks in the primary region allowed to connect to PostgreSQL (0.0.0.0/0 is forbidden)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.primary_allowed_cidr_blocks : can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0"])
    error_message = "All primary_allowed_cidr_blocks must be valid IPv4 CIDRs and cannot include 0.0.0.0/0."
  }
}

variable "secondary_allowed_cidr_blocks" {
  description = "Optional IPv4 CIDR blocks in the secondary region allowed to connect to PostgreSQL (0.0.0.0/0 is forbidden)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.secondary_allowed_cidr_blocks : can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0"])
    error_message = "All secondary_allowed_cidr_blocks must be valid IPv4 CIDRs and cannot include 0.0.0.0/0."
  }
}

variable "iam_auth_db_users" {
  description = "PostgreSQL database usernames granted rds-db:connect via IAM in both regions. Defaults to [database_name]."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_auth_db_users : can(regex("^[a-z][a-z0-9_]{0,62}$", u))])
    error_message = "Each username in iam_auth_db_users must start with a lowercase letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "service_iam_role_names" {
  description = "Optional list of existing EKS service IAM role names (IRSA / EKS Pod Identity) to attach the rds-db:connect IAM policy to."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------
# Backups, maintenance & data protection
# ------------------------------------------------------------------------------

variable "backup_retention_period" {
  description = "Automated backup retention period in days for point-in-time recovery (7-35 days; defaults to maximum 35 days for customer/payment data)."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 7 and 35 days for production data protection."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC backup window (must not overlap with preferred_maintenance_window)."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC maintenance window for minor upgrades and OS patches."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Protect the global cluster and both regional clusters against accidental deletion."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot if the primary cluster is ever destroyed (should remain false in production)."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply modifications immediately rather than during the maintenance window."
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Automatically apply minor Aurora PostgreSQL security and bug-fix releases during the maintenance window."
  type        = bool
  default     = true
}

variable "ca_cert_identifier" {
  description = "RDS CA certificate bundle used for TLS encryption in transit."
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period in days before scheduled deletion of customer-managed KMS keys."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30 days."
  }
}

# ------------------------------------------------------------------------------
# PostgreSQL DBA tuning & audit logging
# ------------------------------------------------------------------------------

variable "pgaudit_log_classes" {
  description = "Statement classes audited by pgaudit (e.g., \"ddl,role\" or \"ddl,role,write\")."
  type        = string
  default     = "ddl,role"
}

variable "slow_query_log_threshold_ms" {
  description = "Log SQL statements taking longer than this many milliseconds."
  type        = number
  default     = 1000

  validation {
    condition     = var.slow_query_log_threshold_ms >= 0
    error_message = "slow_query_log_threshold_ms must be >= 0."
  }
}

variable "idle_in_transaction_session_timeout_ms" {
  description = "Terminate sessions left idle in an open transaction after this duration (ms) to protect vacuum and locks."
  type        = number
  default     = 60000

  validation {
    condition     = var.idle_in_transaction_session_timeout_ms >= 1000
    error_message = "idle_in_transaction_session_timeout_ms must be at least 1000 ms."
  }
}

variable "extra_cluster_parameters" {
  description = "Optional extra or override parameters for the Aurora cluster parameter group in both regions."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "extra_instance_parameters" {
  description = "Optional extra or override parameters for the DB instance parameter group in both regions."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

# ------------------------------------------------------------------------------
# Monitoring, Performance Insights & alerting
# ------------------------------------------------------------------------------

variable "monitoring_interval" {
  description = "RDS Enhanced Monitoring collection interval in seconds (0 disables; 1, 5, 10, 15, 30, or 60)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, or 60."
  }
}

variable "performance_insights_enabled" {
  description = "Enable RDS Performance Insights encrypted with the regional KMS key."
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention in days (7, 731, or a multiple of 31 between 31 and 731)."
  type        = number
  default     = 93

  validation {
    condition     = var.performance_insights_retention_period == 7 || var.performance_insights_retention_period == 731 || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period < 731 && var.performance_insights_retention_period % 31 == 0)
    error_message = "performance_insights_retention_period must be 7, 731, or a multiple of 31 between 31 and 731."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days for exported PostgreSQL and pgaudit logs."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period of at least 30 days."
  }
}

variable "alert_email_addresses" {
  description = "Optional list of email addresses subscribed to database alert SNS topics in both regions."
  type        = list(string)
  default     = []
}

variable "alarm_cpu_threshold" {
  description = "CPU utilization percentage threshold for CloudWatch alerts."
  type        = number
  default     = 80
}

variable "alarm_freeable_memory_bytes" {
  description = "Minimum freeable memory threshold in bytes (default 1 GiB)."
  type        = number
  default     = 1073741824
}

variable "alarm_free_local_storage_bytes" {
  description = "Minimum free local storage threshold in bytes (default 5 GiB)."
  type        = number
  default     = 5368709120
}

variable "alarm_connections_threshold" {
  description = "Maximum database connection count before alarming."
  type        = number
  default     = 500
}

variable "alarm_replica_lag_ms" {
  description = "Maximum intra-region Aurora replica lag in milliseconds before alarming."
  type        = number
  default     = 2000
}

variable "alarm_global_replication_lag_ms" {
  description = "Maximum cross-region Aurora Global Database replication lag in milliseconds before alarming (RPO guardrail)."
  type        = number
  default     = 5000
}

# ------------------------------------------------------------------------------
# Governance & tagging
# ------------------------------------------------------------------------------

variable "data_classification" {
  description = "Data sensitivity classification tag (customer and payment databases default to confidential)."
  type        = string
  default     = "confidential"
}

variable "tags" {
  description = "Additional tags merged onto all provisioned resources."
  type        = map(string)
  default     = {}
}
