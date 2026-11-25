variable "service_name" {
  description = "Identifier of the owning customer-facing service (for example, 'checkout' or 'payments'). Used for naming clusters, KMS aliases, IAM policies, and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-30 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Target deployment environment ('prod' or 'staging'). Selects the network team's 'apps-<environment>' VPC in each region."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "environment must be either 'prod' or 'staging'."
  }
}

variable "primary_region" {
  description = "Primary US AWS region hosting the active writer cluster of the Aurora Global Database."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-(east|west)-[1-9]$", var.primary_region))
    error_message = "primary_region must be a commercial US AWS region (for example, 'us-east-1' or 'us-east-2')."
  }
}

variable "secondary_region" {
  description = "Secondary US AWS region hosting the hot-standby Aurora Global Database cluster for rapid cross-region failover."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-(east|west)-[1-9]$", var.secondary_region))
    error_message = "secondary_region must be a commercial US AWS region (for example, 'us-west-2' or 'us-east-2')."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name created on the cluster. Defaults to service_name with hyphens converted to underscores."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier (1-63 characters, starting with a letter or underscore, containing only letters, digits, and underscores)."
  }
}

variable "master_username" {
  description = "Master administrative username for the Aurora cluster. Avoids common default superuser names ('postgres', 'admin'); password is managed and rotated in AWS Secrets Manager."
  type        = string
  default     = "dbadmin"

  validation {
    condition = (
      can(regex("^[a-zA-Z][a-zA-Z0-9_]{2,62}$", var.master_username)) &&
      !contains(["postgres", "admin", "rdsadmin", "rdsrepladmin", "root", "user"], lower(var.master_username))
    )
    error_message = "master_username must be 3-63 characters starting with a letter, contain only letters, digits, or underscores, and not use default/reserved names ('postgres', 'admin', 'rdsadmin', 'root')."
  }
}

variable "iam_database_users" {
  description = "PostgreSQL role names permitted to authenticate with short-lived IAM tokens (rds-db:connect) from EKS workloads. When empty, defaults to a single role matching the resolved database_name."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_database_users : can(regex("^[a-zA-Z_][a-zA-Z0-9_-]{0,62}$", u))])
    error_message = "Every entry in iam_database_users must be an explicit PostgreSQL role identifier (wildcards like '*' are prohibited)."
  }
}

variable "service_iam_role_names" {
  description = "Optional IAM role names (such as EKS IRSA or Pod Identity roles) to which the module attaches the multi-region rds-db:connect IAM policy."
  type        = set(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Per-region security group IDs (for example, EKS pod or node security groups) permitted inbound TCP access to PostgreSQL."
  type = object({
    primary   = optional(set(string), [])
    secondary = optional(set(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "Per-region private IPv4 CIDR blocks permitted inbound TCP access to PostgreSQL. Public 0.0.0.0/0 CIDRs are rejected."
  type = object({
    primary   = optional(set(string), [])
    secondary = optional(set(string), [])
  })
  default = {}

  validation {
    condition = (
      !contains(coalesce(var.allowed_cidr_blocks.primary, toset([])), "0.0.0.0/0") &&
      !contains(coalesce(var.allowed_cidr_blocks.secondary, toset([])), "0.0.0.0/0") &&
      alltrue([for c in coalesce(var.allowed_cidr_blocks.primary, toset([])) : can(cidrhost(c, 0))]) &&
      alltrue([for c in coalesce(var.allowed_cidr_blocks.secondary, toset([])) : can(cidrhost(c, 0))])
    )
    error_message = "allowed_cidr_blocks must contain valid IPv4 CIDRs and must never include '0.0.0.0/0'."
  }
}

variable "allow_vpc_cidr_fallback" {
  description = "When true and neither allowed_security_group_ids nor allowed_cidr_blocks are specified for a region, allow PostgreSQL ingress from that region's apps-<environment> VPC CIDR so EKS pods using AWS VPC CNI can connect."
  type        = bool
  default     = true
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

variable "engine_major_version" {
  description = "Aurora PostgreSQL major version ('16' or '17') used when engine_version is not explicitly pinned."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["16", "17"], var.engine_major_version)
    error_message = "engine_major_version must be a supported current Aurora PostgreSQL major version ('16' or '17')."
  }
}

variable "engine_version" {
  description = "Optional exact Aurora PostgreSQL engine version (for example, '16.15'). When null, selects the latest Global Database-capable minor version of engine_major_version."
  type        = string
  default     = null
  nullable    = true
}

variable "instance_class" {
  description = "Aurora DB instance class across both regions. Supports production memory-optimized classes (such as 'db.r8g.large', 'db.r7g.xlarge') or 'db.serverless' for Aurora Serverless v2."
  type        = string
  default     = "db.r8g.large"

  validation {
    condition     = var.instance_class == "db.serverless" || can(regex("^db\\.(r[6-9]g?|x2g?)\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be a production memory-optimized Aurora class (db.r6g/r7g/r8g/r6i/r7i/x2g) or 'db.serverless'. Burstable db.t* instances are disallowed."
  }
}

variable "serverlessv2_scaling" {
  description = "Aurora Serverless v2 ACU scaling bounds applied to clusters when instance_class is 'db.serverless'."
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = {
    min_capacity = 2
    max_capacity = 16
  }

  validation {
    condition = (
      var.serverlessv2_scaling.min_capacity >= 0.5 &&
      var.serverlessv2_scaling.max_capacity <= 256 &&
      var.serverlessv2_scaling.min_capacity <= var.serverlessv2_scaling.max_capacity
    )
    error_message = "serverlessv2_scaling requires 0.5 <= min_capacity <= max_capacity <= 256."
  }
}

variable "primary_instance_count" {
  description = "Baseline number of Aurora instances in the primary region (1 writer plus Multi-AZ readers). Must be at least 2 in 'prod'."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 15 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be an integer between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Baseline number of warm Multi-AZ reader instances in the secondary region so cross-region failover serves full production traffic within minutes. Must be at least 2 in 'prod'."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be an integer between 1 and 15."
  }
}

variable "enable_read_autoscaling" {
  description = "Enable Application Auto Scaling for Aurora read replicas in both regions (automatically bypassed when instance_class is 'db.serverless')."
  type        = bool
  default     = true
}

variable "max_read_replica_count" {
  description = "Maximum number of read replicas Application Auto Scaling may maintain in each region."
  type        = number
  default     = 6

  validation {
    condition     = var.max_read_replica_count >= 2 && var.max_read_replica_count <= 15 && floor(var.max_read_replica_count) == var.max_read_replica_count
    error_message = "max_read_replica_count must be an integer between 2 and 15."
  }
}

variable "read_autoscaling_target_cpu" {
  description = "Target average CPU utilization percentage for Aurora read replica auto-scaling."
  type        = number
  default     = 70

  validation {
    condition     = var.read_autoscaling_target_cpu >= 20 && var.read_autoscaling_target_cpu <= 90
    error_message = "read_autoscaling_target_cpu must be between 20 and 90."
  }
}

variable "storage_type" {
  description = "Aurora cluster storage configuration. Defaults to 'aurora-iopt1' (Aurora I/O-Optimized) for predictable cost and low write latency on transactional workloads."
  type        = string
  default     = "aurora-iopt1"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be either 'aurora' or 'aurora-iopt1'."
  }
}

variable "enable_global_write_forwarding" {
  description = "Enable Aurora Global Database write forwarding on the secondary cluster so secondary-region readers can forward occasional write statements to the primary writer."
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Continuous backup and Point-in-Time Recovery (PITR) retention window in days."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period must be an integer between 7 and 35 days for production customer and payment databases."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the global and regional Aurora clusters."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip creating a final DB cluster snapshot when destroying the primary Aurora cluster."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply cluster and instance modifications immediately rather than waiting for the regional maintenance window."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Retention period in days for KMS-encrypted PostgreSQL and IAM auth audit logs in CloudWatch Logs."
  type        = number
  default     = 365

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention period of at least 30 days."
  }
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring OS metrics collection interval in seconds."
  type        = number
  default     = 60

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 1, 5, 10, 15, 30, or 60 seconds."
  }
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days (7 days free tier, 31-713 in multiples of 31, or 731 days)."
  type        = number
  default     = 7

  validation {
    condition = (
      var.performance_insights_retention_period == 7 ||
      var.performance_insights_retention_period == 731 ||
      (
        var.performance_insights_retention_period >= 31 &&
        var.performance_insights_retention_period <= 713 &&
        var.performance_insights_retention_period % 31 == 0
      )
    )
    error_message = "performance_insights_retention_period must be 7, 731, or a multiple of 31 between 31 and 713."
  }
}

variable "slow_query_log_threshold_ms" {
  description = "PostgreSQL log_min_duration_statement threshold in milliseconds; statements exceeding this duration are logged."
  type        = number
  default     = 1000

  validation {
    condition     = var.slow_query_log_threshold_ms >= 100 && var.slow_query_log_threshold_ms <= 60000
    error_message = "slow_query_log_threshold_ms must be between 100 and 60000 ms."
  }
}

variable "idle_in_transaction_timeout_ms" {
  description = "PostgreSQL idle_in_transaction_session_timeout in milliseconds to prevent abandoned sessions from holding row locks or blocking autovacuum."
  type        = number
  default     = 60000

  validation {
    condition     = var.idle_in_transaction_timeout_ms >= 5000 && var.idle_in_transaction_timeout_ms <= 600000
    error_message = "idle_in_transaction_timeout_ms must be between 5000 and 600000 ms."
  }
}

variable "replication_lag_alarm_threshold_ms" {
  description = "CloudWatch alarm threshold in milliseconds for AuroraGlobalDBReplicationLag to monitor the cross-region RPO target of a few seconds."
  type        = number
  default     = 5000

  validation {
    condition     = var.replication_lag_alarm_threshold_ms >= 1000 && var.replication_lag_alarm_threshold_ms <= 30000
    error_message = "replication_lag_alarm_threshold_ms must be between 1000 and 30000 ms."
  }
}

variable "alarm_sns_topic_arns" {
  description = "Optional regional SNS topic ARNs to receive CloudWatch alarm notifications and RDS cluster/failover event alerts."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "additional_cluster_parameters" {
  description = "Optional additional Aurora PostgreSQL cluster parameters. Mandatory security settings (rds.force_ssl, password_encryption) cannot be overridden."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []

  validation {
    condition = alltrue([
      for p in var.additional_cluster_parameters :
      !contains(["rds.force_ssl", "password_encryption", "shared_preload_libraries"], lower(p.name)) &&
      contains(["immediate", "pending-reboot"], p.apply_method)
    ])
    error_message = "additional_cluster_parameters must use apply_method 'immediate' or 'pending-reboot' and cannot override mandatory security parameters ('rds.force_ssl', 'password_encryption', 'shared_preload_libraries')."
  }
}

variable "tags" {
  description = "Additional tags merged onto all taggable AWS resources created by this module."
  type        = map(string)
  default     = {}
}
