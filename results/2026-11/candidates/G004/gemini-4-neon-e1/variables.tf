################################################################################
# Service Identity & Environment (Required)
################################################################################

variable "service_name" {
  description = "Short, lowercase identifier for the customer-facing service that owns this database (e.g., 'checkout', 'payments'). Used for resource naming, IAM scoping, and tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-24 characters, lowercase alphanumeric with hyphens, starting with a letter and ending with an alphanumeric character."
  }
}

variable "environment" {
  description = "Target environment matching the network team's VPC naming convention ('apps-prod' or 'apps-staging')."
  type        = string

  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "environment must be either 'prod' or 'staging'."
  }
}

################################################################################
# Regional Topology
################################################################################

variable "primary_region" {
  description = "Primary US AWS region hosting the active writer Aurora PostgreSQL cluster."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.primary_region))
    error_message = "primary_region must be a US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "secondary_region" {
  description = "Secondary US AWS region hosting the warm Aurora Global Database replica for rapid cross-region failover."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.secondary_region))
    error_message = "secondary_region must be a US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

################################################################################
# Database Engine & Sizing
################################################################################

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must support Aurora Global Databases."
  type        = string
  default     = "17.9"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be a valid Aurora PostgreSQL major.minor version string (e.g., '17.9')."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name created in the cluster. Defaults to service_name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a lowercase letter and contain only lowercase letters, numbers, and underscores (max 63 characters)."
  }
}

variable "master_username" {
  description = "Master administrator username. Password is automatically generated, encrypted with the primary KMS CMK, and managed in AWS Secrets Manager."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{2,31}$", var.master_username)) && !contains(["admin", "root", "rdsadmin"], var.master_username)
    error_message = "master_username must be 3-32 lowercase alphanumeric/underscore characters, start with a letter, and not be a reserved name (admin, root, rdsadmin)."
  }
}

variable "port" {
  description = "TCP port for PostgreSQL connections."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "port must be a valid non-privileged TCP port between 1024 and 65535."
  }
}

variable "instance_class" {
  description = "DB instance class for primary Aurora PostgreSQL instances. Defaults to Graviton3 memory-optimized db.r7g.large."
  type        = string
  default     = "db.r7g.large"

  validation {
    condition     = can(regex("^db\\.(r[678][gi]|x2g|serverless)", var.instance_class))
    error_message = "instance_class must be a production-grade memory-optimized Aurora instance class (db.r6g/r7g/r8g/r6i/r7i/x2g) or db.serverless."
  }
}

variable "secondary_instance_class" {
  description = "DB instance class for secondary-region Aurora instances. Defaults to instance_class so failover capacity matches primary."
  type        = string
  default     = null

  validation {
    condition     = var.secondary_instance_class == null || can(regex("^db\\.(r[678][gi]|x2g|serverless)", var.secondary_instance_class))
    error_message = "secondary_instance_class must be a production-grade memory-optimized Aurora instance class or db.serverless."
  }
}

variable "primary_instance_count" {
  description = "Number of Aurora instances in the primary region (minimum 2 for Multi-AZ high availability)."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 16
    error_message = "primary_instance_count must be between 2 and 16 to guarantee Multi-AZ failover within the primary region."
  }
}

variable "secondary_instance_count" {
  description = "Number of warm Aurora instances in the secondary region. Defaults to 2 so the secondary region immediately has Multi-AZ HA upon regional failover."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 16
    error_message = "secondary_instance_count must be between 1 and 16 so the secondary region can serve traffic immediately on failover."
  }
}

variable "storage_type" {
  description = "Aurora storage configuration. Leave null for Aurora Standard, or set to 'aurora-iopt1' for Aurora I/O-Optimized workloads with high I/O spend."
  type        = string
  default     = null

  validation {
    condition     = var.storage_type == null || contains(["", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be null, \"\", or 'aurora-iopt1'."
  }
}

variable "enable_global_write_forwarding" {
  description = "Enable Aurora Global Database write forwarding from the secondary cluster to the primary cluster for read-local/write-forwarded workloads."
  type        = bool
  default     = false
}

variable "enable_read_replica_autoscaling" {
  description = "Enable Application Auto Scaling for Aurora read replicas in the primary region based on average CPU utilization."
  type        = bool
  default     = false
}

variable "autoscaling_max_read_replicas" {
  description = "Maximum number of read replicas in the primary region when enable_read_replica_autoscaling is true."
  type        = number
  default     = 5

  validation {
    condition     = var.autoscaling_max_read_replicas >= 1 && var.autoscaling_max_read_replicas <= 15
    error_message = "autoscaling_max_read_replicas must be between 1 and 15."
  }
}

variable "autoscaling_target_cpu" {
  description = "Target average CPU utilization percentage for primary read replica autoscaling."
  type        = number
  default     = 65

  validation {
    condition     = var.autoscaling_target_cpu >= 20 && var.autoscaling_target_cpu <= 90
    error_message = "autoscaling_target_cpu must be between 20 and 90."
  }
}

################################################################################
# Networking & EKS Access Control
################################################################################

variable "primary_allowed_security_group_ids" {
  description = "Security group IDs in the primary region (e.g., EKS pod/node security groups) permitted to connect to PostgreSQL."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "Security group IDs in the secondary region (e.g., EKS pod/node security groups) permitted to connect to PostgreSQL."
  type        = list(string)
  default     = []
}

variable "primary_allowed_cidr_blocks" {
  description = "Optional CIDR blocks in the primary region permitted to connect to PostgreSQL (prefer security group IDs where possible)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.primary_allowed_cidr_blocks : cidr != "0.0.0.0/0" && cidr != "::/0"])
    error_message = "Public CIDR blocks (0.0.0.0/0 or ::/0) are prohibited for database ingress."
  }
}

variable "secondary_allowed_cidr_blocks" {
  description = "Optional CIDR blocks in the secondary region permitted to connect to PostgreSQL (prefer security group IDs where possible)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.secondary_allowed_cidr_blocks : cidr != "0.0.0.0/0" && cidr != "::/0"])
    error_message = "Public CIDR blocks (0.0.0.0/0 or ::/0) are prohibited for database ingress."
  }
}

################################################################################
# IAM Database Authentication (EKS Services)
################################################################################

variable "iam_db_users" {
  description = "PostgreSQL database user names permitted to authenticate via IAM database authentication (rds-db:connect) in both regions. Defaults to [service_name with underscores]."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_db_users : can(regex("^[a-z][a-z0-9_]{0,62}$", u))])
    error_message = "Each entry in iam_db_users must be a valid lowercase PostgreSQL identifier."
  }
}

variable "service_iam_role_names" {
  description = "Optional list of existing EKS service IAM role names (IRSA / EKS Pod Identity) to automatically attach the multi-region rds-db:connect IAM policy to."
  type        = list(string)
  default     = []
}

################################################################################
# Backups, Maintenance & Lifecycle Safety
################################################################################

variable "backup_retention_period" {
  description = "Automated continuous backup (PITR) retention period in days. Defaults to 35 days for prod and 7 days for staging."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_period == null || (var.backup_retention_period >= 1 && var.backup_retention_period <= 35)
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC time window for automated backups. Must not overlap preferred_maintenance_window."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC maintenance window for minor patches and OS updates."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Protect the global cluster and regional clusters from accidental deletion. Defaults to true in prod and false in staging."
  type        = bool
  default     = null
}

variable "skip_final_snapshot" {
  description = "Whether to skip creating a final cluster snapshot on deletion. Defaults to false in prod and true in staging."
  type        = bool
  default     = null
}

variable "apply_immediately" {
  description = "Whether cluster/instance modifications are applied immediately rather than during the maintenance window. Defaults to false in prod and true in staging."
  type        = bool
  default     = null
}

variable "auto_minor_version_upgrade" {
  description = "Automatically apply minor PostgreSQL security and bug-fix upgrades during the maintenance window."
  type        = bool
  default     = true
}

variable "allow_major_version_upgrade" {
  description = "Allow major PostgreSQL version upgrades. Kept false by default to prevent unintended disruptive upgrades."
  type        = bool
  default     = false
}

################################################################################
# Security, Auditing & PostgreSQL Tuning
################################################################################

variable "kms_deletion_window_in_days" {
  description = "Waiting period in days before scheduled deletion of regional KMS keys."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30 days."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days for exported PostgreSQL and IAM auth logs. Defaults to 365 days in prod (12-month audit retention) and 30 days in staging."
  type        = number
  default     = null

  validation {
    condition     = var.log_retention_days == null || contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention period."
  }
}

variable "pgaudit_log" {
  description = "Classes of statements logged by pgaudit (e.g., 'ddl,role'). Avoid 'all' on high-write payment databases unless required to prevent PII/write-amplification in logs."
  type        = string
  default     = "ddl,role"
}

variable "statement_timeout_ms" {
  description = "Default PostgreSQL statement_timeout in milliseconds to protect production databases from runaway queries."
  type        = number
  default     = 30000

  validation {
    condition     = var.statement_timeout_ms >= 0 && var.statement_timeout_ms <= 3600000
    error_message = "statement_timeout_ms must be between 0 (disabled) and 3600000 (1 hour)."
  }
}

variable "idle_in_transaction_session_timeout_ms" {
  description = "PostgreSQL idle_in_transaction_session_timeout in milliseconds to terminate leaked transactions from EKS pods."
  type        = number
  default     = 60000

  validation {
    condition     = var.idle_in_transaction_session_timeout_ms >= 1000 && var.idle_in_transaction_session_timeout_ms <= 3600000
    error_message = "idle_in_transaction_session_timeout_ms must be between 1000 ms and 3600000 ms."
  }
}

variable "slow_query_log_threshold_ms" {
  description = "Minimum query duration in milliseconds (log_min_duration_statement) before logging slow queries to CloudWatch."
  type        = number
  default     = 1000

  validation {
    condition     = var.slow_query_log_threshold_ms >= -1
    error_message = "slow_query_log_threshold_ms must be -1 (disabled) or >= 0."
  }
}

variable "additional_cluster_parameters" {
  description = "Optional extra Aurora cluster parameter overrides for service-specific tuning."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "additional_instance_parameters" {
  description = "Optional extra DB instance parameter overrides for service-specific tuning."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

################################################################################
# Observability & Alerting
################################################################################

variable "monitoring_interval" {
  description = "Enhanced Monitoring OS-level metric collection interval in seconds (0, 1, 5, 10, 15, 30, or 60)."
  type        = number
  default     = 15

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, or 60."
  }
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days (7 for free tier, or multiples of 31 up to 731). Defaults to 93 days in prod and 7 days in staging."
  type        = number
  default     = null

  validation {
    condition     = var.performance_insights_retention_period == null || var.performance_insights_retention_period == 7 || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 731 && var.performance_insights_retention_period % 31 == 0)
    error_message = "performance_insights_retention_period must be 7 or a multiple of 31 between 31 and 731."
  }
}

variable "primary_alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN in the primary region for CloudWatch alarms and RDS failover events. If null, a KMS-encrypted SNS topic is created."
  type        = string
  default     = null
}

variable "secondary_alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN in the secondary region for CloudWatch alarms and RDS failover events. If null, a KMS-encrypted SNS topic is created."
  type        = string
  default     = null
}

variable "cpu_alarm_threshold_percent" {
  description = "CloudWatch alarm threshold for average cluster CPU utilization (%)."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold_percent > 0 && var.cpu_alarm_threshold_percent <= 100
    error_message = "cpu_alarm_threshold_percent must be between 1 and 100."
  }
}

variable "freeable_memory_alarm_threshold_bytes" {
  description = "Optional CloudWatch alarm threshold in bytes for low FreeableMemory. Defaults to ~10% of instance RAM for standard r6/r7/r8 classes (1 GiB fallback)."
  type        = number
  default     = null
}

variable "database_connections_alarm_threshold" {
  description = "CloudWatch alarm threshold for DatabaseConnections on the cluster."
  type        = number
  default     = 500

  validation {
    condition     = var.database_connections_alarm_threshold > 0
    error_message = "database_connections_alarm_threshold must be greater than 0."
  }
}

variable "global_replication_lag_alarm_threshold_ms" {
  description = "CloudWatch alarm threshold in milliseconds for AuroraGlobalDBReplicationLag on the secondary cluster, enforcing the cross-region RPO objective."
  type        = number
  default     = 2000

  validation {
    condition     = var.global_replication_lag_alarm_threshold_ms >= 500
    error_message = "global_replication_lag_alarm_threshold_ms must be at least 500 ms."
  }
}

variable "replica_lag_alarm_threshold_ms" {
  description = "CloudWatch alarm threshold in milliseconds for in-region AuroraReplicaLag on reader instances."
  type        = number
  default     = 1000
}

variable "commit_latency_alarm_threshold_ms" {
  description = "CloudWatch alarm threshold in milliseconds for writer CommitLatency."
  type        = number
  default     = 50
}

################################################################################
# Governance & Tagging
################################################################################

variable "data_classification" {
  description = "Data sensitivity classification tag applied to all resources."
  type        = string
  default     = "restricted-pci-pii"
}

variable "owner_team" {
  description = "Owning engineering team tag for cost allocation and incident routing."
  type        = string
  default     = "platform"
}

variable "tags" {
  description = "Additional tags merged onto all module-managed resources across both regions."
  type        = map(string)
  default     = {}
}
