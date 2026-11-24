################################################################################
# Service-Specific Inputs (Required)
################################################################################

variable "service_name" {
  description = "Short, unique name of the service owning this database (e.g. 'checkout', 'payments'). Used to derive cluster, KMS, IAM, and security group identifiers."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-32 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Target environment. Determines which network-team VPC ('apps-staging' or 'apps-prod') is discovered in both US regions."
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
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be 1-63 characters, start with a lowercase letter, and contain only lowercase letters, digits, and underscores."
  }
}

variable "owner_team" {
  description = "Platform or product team responsible for this database (applied as an ownership tag for incident response, auditing, and cost allocation)."
  type        = string

  validation {
    condition     = length(trimspace(var.owner_team)) > 0
    error_message = "owner_team must not be empty."
  }
}

################################################################################
# Regional Topology (US Multi-Region Aurora Global Database)
################################################################################

variable "primary_region" {
  description = "Primary (writer) AWS US region for the Aurora Global Database."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "primary_region must be a US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "secondary_region" {
  description = "Secondary (warm standby / failover) AWS US region for the Aurora Global Database. Must differ from primary_region."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region)
    error_message = "secondary_region must be a US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

################################################################################
# Engine & Compute Sizing
################################################################################

variable "engine_version" {
  description = "Pinned Aurora PostgreSQL engine version. Explicitly pinned so upgrades are intentional and coordinated across both regions."
  type        = string
  default     = "17.9"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be an explicit major.minor Aurora PostgreSQL version (e.g. '17.9')."
  }
}

variable "instance_class" {
  description = "DB instance class for primary region instances (e.g. 'db.r7g.large' or 'db.serverless' for Aurora Serverless v2). Defaults to Graviton3 memory-optimized."
  type        = string
  default     = "db.r7g.large"

  validation {
    condition     = can(regex("^db\\.(serverless|[a-z][0-9][a-z0-9-]*\\.[a-z0-9]+)$", var.instance_class))
    error_message = "instance_class must be a valid RDS instance class (e.g. 'db.r7g.large') or 'db.serverless'."
  }
}

variable "secondary_instance_class" {
  description = "DB instance class for secondary region warm-standby instances. Defaults to var.instance_class so failover capacity matches primary immediately."
  type        = string
  default     = null

  validation {
    condition     = var.secondary_instance_class == null || can(regex("^db\\.(serverless|[a-z][0-9][a-z0-9-]*\\.[a-z0-9]+)$", var.secondary_instance_class))
    error_message = "secondary_instance_class must be null, a valid RDS instance class, or 'db.serverless'."
  }
}

variable "primary_instance_count" {
  description = "Number of Aurora instances in the primary region (1 writer + N-1 readers across AZs). Default 2 provides local Multi-AZ HA."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 15 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be an integer between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of warm Aurora instances in the secondary region. Must be >= 1 (never headless) to meet sub-minute regional RTO. Default 2 provides immediate Multi-AZ HA after failover."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be an integer between 1 and 15 (headless secondary clusters cannot meet sub-minute RTO)."
  }
}

variable "storage_type" {
  description = "Aurora cluster storage configuration: 'aurora' (Standard) or 'aurora-iopt1' (I/O-Optimized for I/O-intensive workloads)."
  type        = string
  default     = "aurora"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be either 'aurora' or 'aurora-iopt1'."
  }
}

variable "serverlessv2_min_capacity" {
  description = "Minimum Aurora Capacity Units (ACUs) when instance_class is 'db.serverless'. Must be >= 0.5 (never 0) to avoid cold-start pause latency."
  type        = number
  default     = 2

  validation {
    condition     = var.serverlessv2_min_capacity >= 0.5 && var.serverlessv2_min_capacity <= 256
    error_message = "serverlessv2_min_capacity must be between 0.5 and 256 ACUs."
  }
}

variable "serverlessv2_max_capacity" {
  description = "Maximum Aurora Capacity Units (ACUs) when instance_class is 'db.serverless'."
  type        = number
  default     = 16

  validation {
    condition     = var.serverlessv2_max_capacity >= 1 && var.serverlessv2_max_capacity <= 256
    error_message = "serverlessv2_max_capacity must be between 1 and 256 ACUs."
  }
}

variable "enable_global_write_forwarding" {
  description = "Allow the secondary region cluster to forward write statements to the primary cluster. Disabled by default to avoid unexpected cross-region write latency unless opted in."
  type        = bool
  default     = false
}

################################################################################
# Network Access & IAM Authentication
################################################################################

variable "port" {
  description = "TCP port on which PostgreSQL listens."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "port must be between 1024 and 65535."
  }
}

variable "primary_allowed_security_group_ids" {
  description = "EKS node or pod security group IDs in the primary region permitted to connect to Aurora on var.port. Defaults to empty (fail-closed)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for sg in var.primary_allowed_security_group_ids : can(regex("^sg-[a-f0-9]+$", sg))])
    error_message = "All entries in primary_allowed_security_group_ids must be valid AWS security group IDs (sg-...)."
  }
}

variable "secondary_allowed_security_group_ids" {
  description = "EKS node or pod security group IDs in the secondary region permitted to connect to Aurora on var.port. Defaults to empty (fail-closed)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for sg in var.secondary_allowed_security_group_ids : can(regex("^sg-[a-f0-9]+$", sg))])
    error_message = "All entries in secondary_allowed_security_group_ids must be valid AWS security group IDs (sg-...)."
  }
}

variable "primary_allowed_cidr_blocks" {
  description = "Optional private CIDR blocks in the primary region permitted to connect to Aurora on var.port (e.g. EKS pod/node subnets). Public 0.0.0.0/0 is rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.primary_allowed_cidr_blocks : can(cidrhost(c, 0)) && c != "0.0.0.0/0" && c != "::/0"])
    error_message = "All entries in primary_allowed_cidr_blocks must be valid CIDRs and must not be 0.0.0.0/0 or ::/0."
  }
}

variable "secondary_allowed_cidr_blocks" {
  description = "Optional private CIDR blocks in the secondary region permitted to connect to Aurora on var.port (e.g. EKS pod/node subnets). Public 0.0.0.0/0 is rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.secondary_allowed_cidr_blocks : can(cidrhost(c, 0)) && c != "0.0.0.0/0" && c != "::/0"])
    error_message = "All entries in secondary_allowed_cidr_blocks must be valid CIDRs and must not be 0.0.0.0/0 or ::/0."
  }
}

variable "master_username" {
  description = "Break-glass administrative master username (password is generated and rotated by AWS Secrets Manager, never stored in state)."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{2,31}$", var.master_username)) && !contains(["rdsadmin", "admin", "root"], var.master_username)
    error_message = "master_username must be 3-32 lowercase alphanumeric/underscore characters, start with a letter, and not be a reserved name."
  }
}

variable "db_iam_usernames" {
  description = "PostgreSQL database role names allowed to connect via IAM database authentication (rds-db:connect) in BOTH regions. Defaults to [replace(var.service_name, '-', '_')]."
  type        = list(string)
  default     = null

  validation {
    condition     = var.db_iam_usernames == null || (length(var.db_iam_usernames) > 0 && alltrue([for u in var.db_iam_usernames : can(regex("^[a-z][a-z0-9_]{0,62}$", u))]))
    error_message = "Each db_iam_usernames entry must be a valid lowercase PostgreSQL identifier (1-63 chars)."
  }
}

variable "service_iam_role_names" {
  description = "Optional list of existing EKS service IAM role names (IRSA / Pod Identity) to automatically attach the module's least-privilege rds-db:connect IAM policy."
  type        = list(string)
  default     = []
}

################################################################################
# Backup, Maintenance & Data Protection
################################################################################

variable "backup_retention_period" {
  description = "Days to retain automated continuous backups for point-in-time recovery (PITR). Defaults to maximum 35 days for production customer/payment data."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period must be an integer between 7 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC backup window (must not overlap with preferred_maintenance_window)."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC maintenance window (must not overlap with preferred_backup_window)."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Protect the global cluster and both regional clusters from accidental deletion. Enabled by default for production safety."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip taking a final DB cluster snapshot when destroying the primary cluster. False by default to prevent accidental data loss."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply cluster/instance modifications immediately instead of during the maintenance window. False by default to prevent unplanned production restarts."
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Allow automatic minor engine security patches during the maintenance window."
  type        = bool
  default     = true
}

variable "kms_deletion_window_days" {
  description = "Waiting period in days before a scheduled KMS CMK deletion takes effect."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30 days."
  }
}

################################################################################
# Security, Auditing & PostgreSQL Operational Guardrails
################################################################################

variable "data_classification" {
  description = "Data sensitivity classification tag applied to all database, encryption, and logging resources."
  type        = string
  default     = "restricted"

  validation {
    condition     = contains(["confidential", "restricted"], var.data_classification)
    error_message = "data_classification must be 'confidential' or 'restricted' for customer/payment databases."
  }
}

variable "pgaudit_log" {
  description = "Classes of statements logged by pgaudit (e.g. 'ddl,role' or 'ddl,role,write'). Bind parameters are disabled by default to avoid logging raw PII/payment fields."
  type        = string
  default     = "ddl,role"
}

variable "slow_query_log_ms" {
  description = "Threshold in milliseconds for PostgreSQL log_min_duration_statement."
  type        = number
  default     = 1000

  validation {
    condition     = var.slow_query_log_ms >= 0
    error_message = "slow_query_log_ms must be >= 0."
  }
}

variable "statement_timeout_ms" {
  description = "Maximum execution time in milliseconds for a single SQL statement (guards against runaway queries starving customer traffic)."
  type        = number
  default     = 30000

  validation {
    condition     = var.statement_timeout_ms >= 1000
    error_message = "statement_timeout_ms must be >= 1000 ms."
  }
}

variable "idle_in_transaction_timeout_ms" {
  description = "Terminate sessions idle inside an open transaction after this many milliseconds (prevents leaked connections from blocking autovacuum and holding locks)."
  type        = number
  default     = 60000

  validation {
    condition     = var.idle_in_transaction_timeout_ms >= 5000
    error_message = "idle_in_transaction_timeout_ms must be >= 5000 ms."
  }
}

variable "lock_timeout_ms" {
  description = "Maximum wait time in milliseconds to acquire a lock (prevents DDL/migrations from queuing production traffic)."
  type        = number
  default     = 10000

  validation {
    condition     = var.lock_timeout_ms >= 1000
    error_message = "lock_timeout_ms must be >= 1000 ms."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days for PostgreSQL audit and IAM authentication error logs. Default 365 days satisfies PCI-DSS Requirement 10."
  type        = number
  default     = 365

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention period of at least 30 days."
  }
}

variable "extra_cluster_parameters" {
  description = "Optional additional Aurora PostgreSQL cluster parameters for service-specific tuning."
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
  description = "RDS Enhanced Monitoring OS metrics collection interval in seconds (0 disables Enhanced Monitoring)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "performance_insights_retention_period" {
  description = "Days to retain RDS Performance Insights data (7 is included free; paid tiers up to 731 days)."
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "performance_insights_retention_period must be 7 or a valid multiple of 31 days up to 731."
  }
}

variable "primary_alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN in the primary region for CloudWatch alarms and RDS events. If null, the module creates a KMS-encrypted SNS topic."
  type        = string
  default     = null
}

variable "secondary_alarm_sns_topic_arn" {
  description = "Optional existing SNS topic ARN in the secondary region for CloudWatch alarms and RDS events. If null, the module creates a KMS-encrypted SNS topic."
  type        = string
  default     = null
}

variable "global_replication_lag_alarm_ms" {
  description = "CloudWatch alarm threshold in milliseconds for AuroraGlobalDBReplicationLag on the secondary cluster (guards the business RPO of a few seconds)."
  type        = number
  default     = 5000

  validation {
    condition     = var.global_replication_lag_alarm_ms >= 500
    error_message = "global_replication_lag_alarm_ms must be >= 500 ms."
  }
}

variable "cpu_alarm_threshold_percent" {
  description = "Cluster CPUUtilization alarm threshold (%)."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold_percent > 0 && var.cpu_alarm_threshold_percent <= 100
    error_message = "cpu_alarm_threshold_percent must be between 1 and 100."
  }
}

variable "freeable_memory_alarm_threshold_bytes" {
  description = "Cluster FreeableMemory low-water alarm threshold in bytes (default 2 GiB, tuned for db.r7g.large 16 GiB RAM)."
  type        = number
  default     = 2147483648

  validation {
    condition     = var.freeable_memory_alarm_threshold_bytes > 0
    error_message = "freeable_memory_alarm_threshold_bytes must be > 0."
  }
}

variable "connections_alarm_threshold" {
  description = "Cluster DatabaseConnections high-water alarm threshold."
  type        = number
  default     = 800

  validation {
    condition     = var.connections_alarm_threshold > 0
    error_message = "connections_alarm_threshold must be > 0."
  }
}

variable "additional_tags" {
  description = "Additional tags merged onto all taggable resources."
  type        = map(string)
  default     = {}
}
