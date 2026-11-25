# -----------------------------------------------------------------------------
# Service & Topology Identification (Required)
# -----------------------------------------------------------------------------

variable "service_name" {
  description = "Name of the service owning this database (e.g. 'checkout', 'payments'). Used to name AWS resources, default database name, and IAM DB principals."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,34}[a-z0-9]$", var.service_name)) && !can(regex("--", var.service_name))
    error_message = "service_name must be 3-36 characters of lowercase letters, digits, and single hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "primary_region" {
  description = "Primary US AWS region hosting the active Aurora writer cluster (e.g. 'us-east-1')."
  type        = string

  validation {
    condition     = can(regex("^us-(east|west)-[1-9][0-9]*$", var.primary_region))
    error_message = "primary_region must be a commercial US AWS region (e.g. 'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2')."
  }
}

variable "secondary_region" {
  description = "Secondary US AWS region hosting the warm Aurora Global Database standby/reader cluster for fast regional failover (e.g. 'us-west-2')."
  type        = string

  validation {
    condition     = can(regex("^us-(east|west)-[1-9][0-9]*$", var.secondary_region))
    error_message = "secondary_region must be a commercial US AWS region (e.g. 'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2')."
  }
}

# -----------------------------------------------------------------------------
# Environment & Network Access
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Target network environment ('prod' or 'staging', or explicit VPC name 'apps-prod' / 'apps-staging'). Determines VPC and 'tier = database' subnet discovery in both regions."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "apps-prod", "apps-staging"], var.environment)
    error_message = "environment must be one of 'prod', 'staging', 'apps-prod', or 'apps-staging'."
  }
}

variable "allowed_security_group_ids" {
  description = "Optional existing security group IDs (such as EKS node or pod security groups) allowed to connect to PostgreSQL in each region, in addition to the dedicated client security groups created by this module."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "Optional private IPv4 CIDR blocks (such as EKS pod subnets) allowed to connect to PostgreSQL in each region. Unrestricted CIDRs (0.0.0.0/0) are prohibited."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}

  validation {
    condition = alltrue([
      for cidr in concat(var.allowed_cidr_blocks.primary, var.allowed_cidr_blocks.secondary) :
      can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0"
    ])
    error_message = "All allowed_cidr_blocks must be valid IPv4 CIDRs and must not be '0.0.0.0/0'."
  }
}

# -----------------------------------------------------------------------------
# Database Identity & EKS IAM Authentication
# -----------------------------------------------------------------------------

variable "database_name" {
  description = "Initial PostgreSQL database name. Defaults to service_name with hyphens converted to underscores."
  type        = string
  default     = null

  validation {
    condition = (
      var.database_name == null ||
      (
        can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name)) &&
        !contains(["postgres", "rdsadmin", "template0", "template1"], var.database_name)
      )
    )
    error_message = "database_name must be a valid lowercase PostgreSQL identifier (1-63 chars, letters/digits/underscores, starting with a letter) and not a reserved system database name."
  }
}

variable "master_username" {
  description = "Master administrative username for the Aurora cluster. Password is managed and rotated in AWS Secrets Manager encrypted with a customer-managed KMS key."
  type        = string
  default     = "dbadmin"

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9_]{1,62}$", var.master_username)) &&
      !contains(["postgres", "rdsadmin", "admin", "root", "user"], var.master_username)
    )
    error_message = "master_username must be 2-63 lowercase letters/digits/underscores starting with a letter and must not use predictable/reserved names ('postgres', 'rdsadmin', 'admin', 'root', 'user')."
  }
}

variable "db_iam_users" {
  description = "PostgreSQL database usernames permitted for IAM token authentication (rds-db:connect) by the service's read-write IAM policy across both regions. Defaults to [<database_name>]."
  type        = list(string)
  default     = null

  validation {
    condition = (
      var.db_iam_users == null ||
      (
        length(var.db_iam_users) > 0 &&
        alltrue([for u in var.db_iam_users : can(regex("^[a-z][a-z0-9_]{0,62}$", u))])
      )
    )
    error_message = "db_iam_users must contain one or more valid lowercase PostgreSQL role names."
  }
}

variable "db_readonly_iam_users" {
  description = "PostgreSQL database usernames permitted for IAM token authentication (rds-db:connect) by the read-only IAM policy across both regions. Defaults to ['<database_name>_readonly']."
  type        = list(string)
  default     = null

  validation {
    condition = (
      var.db_readonly_iam_users == null ||
      (
        length(var.db_readonly_iam_users) > 0 &&
        alltrue([for u in var.db_readonly_iam_users : can(regex("^[a-z][a-z0-9_]{0,62}$", u))])
      )
    )
    error_message = "db_readonly_iam_users must contain one or more valid lowercase PostgreSQL role names."
  }
}

variable "service_iam_roles" {
  description = "Optional existing EKS workload IAM role names or ARNs (IRSA / EKS Pod Identity) to attach the multi-region read-write rds-db:connect IAM policy to."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for r in var.service_iam_roles :
      can(regex("^(arn:aws(-[a-z]+)?:iam::[0-9]{12}:role/(.+/)?)?[\\w+=,.@-]{1,64}$", r))
    ])
    error_message = "Each entry in service_iam_roles must be a valid IAM role name or IAM role ARN."
  }
}

variable "readonly_iam_roles" {
  description = "Optional existing IAM role names or ARNs to attach the multi-region read-only rds-db:connect IAM policy to."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for r in var.readonly_iam_roles :
      can(regex("^(arn:aws(-[a-z]+)?:iam::[0-9]{12}:role/(.+/)?)?[\\w+=,.@-]{1,64}$", r))
    ])
    error_message = "Each entry in readonly_iam_roles must be a valid IAM role name or IAM role ARN."
  }
}

variable "port" {
  description = "TCP port on which Aurora PostgreSQL accepts connections."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port must be between 1150 and 65535."
  }
}

# -----------------------------------------------------------------------------
# Engine, Compute & High Availability / DR Sizing
# -----------------------------------------------------------------------------

variable "engine_major_version" {
  description = "Aurora PostgreSQL major version used when engine_version is not explicitly pinned (e.g. '16' or '17')."
  type        = string
  default     = "16"

  validation {
    condition     = contains(["15", "16", "17"], var.engine_major_version)
    error_message = "engine_major_version must be a supported Aurora PostgreSQL major version ('15', '16', or '17')."
  }
}

variable "engine_version" {
  description = "Optional exact Aurora PostgreSQL engine version (e.g. '16.15'). When null, the latest available minor version for engine_major_version is discovered automatically."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "Aurora DB instance class for cluster instances in both regions (e.g. 'db.r7g.large', 'db.r8g.xlarge', or 'db.serverless')."
  type        = string
  default     = "db.r7g.large"

  validation {
    condition     = can(regex("^db\\.(serverless|[a-z0-9]+\\.[a-z0-9]+)$", var.instance_class))
    error_message = "instance_class must be 'db.serverless' or a valid RDS provisioned instance class starting with 'db.'."
  }
}

variable "serverlessv2_scaling" {
  description = "Aurora Serverless v2 ACU scaling bounds applied when instance_class is 'db.serverless'. Minimum >= 2 ACU keeps buffer caches warm for fast failover."
  type = object({
    min_capacity = optional(number, 2)
    max_capacity = optional(number, 16)
  })
  default = {}

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
  description = "Number of DB instances in the primary region cluster (1 writer + N-1 Multi-AZ readers). Must be >= 2 for Multi-AZ high availability."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be an integer between 2 and 15 to guarantee Multi-AZ availability."
  }
}

variable "secondary_instance_count" {
  description = "Number of warm DB instances in the secondary region cluster. Must be >= 1 (headless clusters violate the minutes-level RTO target); defaults to 2 so the promoted region is immediately Multi-AZ."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be an integer between 1 and 15 (warm compute is required to achieve failover within minutes)."
  }
}

variable "enable_global_write_forwarding" {
  description = "Enable Aurora Global Database write forwarding on the secondary cluster so regional read replicas can transparently forward occasional writes to the primary cluster."
  type        = bool
  default     = true
}

variable "auto_minor_version_upgrade" {
  description = "Automatically apply minor engine security and stability patches during the maintenance window."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Whether cluster and instance modifications are applied immediately instead of waiting for preferred_maintenance_window. Defaults to false to protect production availability."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Storage, Backups, Compliance & Data Protection
# -----------------------------------------------------------------------------

variable "storage_type" {
  description = "Aurora cluster storage configuration. Defaults to 'aurora-iopt1' (Aurora I/O-Optimized) for predictable latency and cost on transactional workloads."
  type        = string
  default     = "aurora-iopt1"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be 'aurora' or 'aurora-iopt1'."
  }
}

variable "backup_retention_period" {
  description = "Continuous backup / point-in-time recovery retention window in days (7-35). Defaults to 35 days for customer and payment data compliance."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period must be an integer between 7 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC window during which automated backups are taken."
  type        = string
  default     = "07:00-08:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC window during which system maintenance and minor patches are applied."
  type        = string
  default     = "sun:08:30-sun:09:30"
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the Aurora Global Database and regional clusters."
  type        = bool
  default     = true
}

variable "final_snapshot_enabled" {
  description = "Create a final cluster snapshot when destroying the primary Aurora cluster."
  type        = bool
  default     = true
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period in days (7-30) before a scheduled customer-managed KMS key deletion completes."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30 && floor(var.kms_deletion_window_in_days) == var.kms_deletion_window_in_days
    error_message = "kms_deletion_window_in_days must be an integer between 7 and 30."
  }
}

# -----------------------------------------------------------------------------
# Observability, Auditing & Tuning
# -----------------------------------------------------------------------------

variable "monitoring_interval" {
  description = "Enhanced Monitoring OS metric collection interval in seconds (1, 5, 10, 15, 30, or 60)."
  type        = number
  default     = 15

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 1, 5, 10, 15, 30, or 60 seconds (Enhanced Monitoring is required for production databases)."
  }
}

variable "performance_insights_retention_period" {
  description = "Performance Insights data retention period in days (7 for free tier, a multiple of 31 up to 713, or 731 for 2 years)."
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
    error_message = "performance_insights_retention_period must be 7, a multiple of 31 between 31 and 713, or 731."
  }
}

variable "log_retention_days" {
  description = "Retention in days for CloudWatch Logs holding PostgreSQL and IAM authentication audit logs. Minimum 90 days for payment/customer data auditability."
  type        = number
  default     = 365

  validation {
    condition     = contains([90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention period of at least 90 days."
  }
}

variable "rpo_replication_lag_alarm_ms" {
  description = "CloudWatch alarm threshold in milliseconds for cross-region AuroraGlobalDBReplicationLag to guard the 'few seconds of writes' RPO target."
  type        = number
  default     = 5000

  validation {
    condition     = var.rpo_replication_lag_alarm_ms >= 1000 && var.rpo_replication_lag_alarm_ms <= 15000
    error_message = "rpo_replication_lag_alarm_ms must be between 1000 ms (1s) and 15000 ms (15s)."
  }
}

variable "alarm_sns_topic_arns" {
  description = "Optional existing regional SNS topic ARNs (e.g. PagerDuty/incident routing) to notify on database alarms in addition to the module-managed encrypted SNS topics."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "cluster_parameters" {
  description = "Optional additional Aurora PostgreSQL cluster parameter overrides merged on top of the module's security and reliability defaults."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []
}

variable "tags" {
  description = "Additional AWS resource tags applied across all regional and global resources."
  type        = map(string)
  default     = {}
}
