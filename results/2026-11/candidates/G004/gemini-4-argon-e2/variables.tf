variable "service_name" {
  description = "Name of the service that owns this Aurora PostgreSQL database (e.g., 'checkout'). Used for naming, tagging, and default database/IAM user derivation."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-40 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Target environment name ('prod', 'staging', 'apps-prod', or 'apps-staging'). Maps to the corresponding regional VPC ('apps-prod' or 'apps-staging')."
  type        = string

  validation {
    condition     = contains(["prod", "staging", "apps-prod", "apps-staging"], var.environment)
    error_message = "environment must be one of: 'prod', 'staging', 'apps-prod', 'apps-staging'."
  }
}

variable "primary_region" {
  description = "Primary US AWS region where the writer Aurora PostgreSQL cluster is deployed."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.primary_region))
    error_message = "primary_region must be a valid US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "secondary_region" {
  description = "Secondary US AWS region where the warm-standby Aurora Global Database secondary cluster is deployed for fast regional failover."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.secondary_region))
    error_message = "secondary_region must be a valid US AWS region (us-east-1, us-east-2, us-west-1, or us-west-2)."
  }
}

variable "database_name" {
  description = "Name of the initial PostgreSQL database created in the cluster. Defaults to service_name with hyphens converted to underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only alphanumeric characters and underscores (max 63 chars)."
  }
}

variable "master_username" {
  description = "Master administrator username for the Aurora PostgreSQL cluster. The master password is automatically managed and rotated in AWS Secrets Manager."
  type        = string
  default     = "postgres_admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{1,62}$", var.master_username))
    error_message = "master_username must start with a letter and contain only letters, digits, and underscores."
  }
}

variable "iam_database_user" {
  description = "PostgreSQL database username allowed via IAM Database Authentication (rds-db:connect) for EKS workloads. Defaults to service_name with hyphens replaced by underscores."
  type        = string
  default     = null
}

variable "service_iam_role_names" {
  description = "Optional set of existing EKS service IAM role names to which the module will attach the rds-db:connect IAM policy."
  type        = set(string)
  default     = []
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "16.4"

  validation {
    condition     = can(regex("^(14|15|16|17)\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be a supported Aurora PostgreSQL major.minor version (14.x, 15.x, 16.x, or 17.x)."
  }
}

variable "instance_class" {
  description = "Aurora DB instance class for cluster instances (e.g., 'db.r6g.large', 'db.r6g.xlarge', or 'db.serverless')."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.(serverless|[a-z0-9]+\\.[a-z0-9]+)$", var.instance_class))
    error_message = "instance_class must be 'db.serverless' or a valid RDS instance class such as 'db.r6g.large'."
  }
}

variable "primary_instance_count" {
  description = "Number of Aurora PostgreSQL instances in the primary region cluster (minimum 2 recommended for Multi-AZ high availability: 1 writer + 1 or more readers)."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of warm-standby Aurora PostgreSQL instances in the secondary region cluster so cross-region failover can serve traffic within minutes."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15 (headless secondary clusters cannot fail over within minutes)."
  }
}

variable "serverlessv2_min_capacity" {
  description = "Minimum Aurora Serverless v2 capacity in ACUs (configured on clusters to support Serverless v2 or mixed instances)."
  type        = number
  default     = 0.5

  validation {
    condition     = var.serverlessv2_min_capacity >= 0.5 && var.serverlessv2_min_capacity <= 128
    error_message = "serverlessv2_min_capacity must be between 0.5 and 128 ACUs."
  }
}

variable "serverlessv2_max_capacity" {
  description = "Maximum Aurora Serverless v2 capacity in ACUs."
  type        = number
  default     = 16

  validation {
    condition     = var.serverlessv2_max_capacity >= 1 && var.serverlessv2_max_capacity <= 256
    error_message = "serverlessv2_max_capacity must be between 1 and 256 ACUs."
  }
}

variable "port" {
  description = "TCP port on which the Aurora PostgreSQL clusters accept connections."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port must be between 1150 and 65535."
  }
}

variable "allow_vpc_cidr_ingress" {
  description = "Whether to allow PostgreSQL ingress traffic from the regional environment VPC CIDR block (where EKS workloads run)."
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks_primary" {
  description = "Additional IPv4 CIDR blocks permitted to connect to the primary Aurora cluster on the PostgreSQL port."
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks_secondary" {
  description = "Additional IPv4 CIDR blocks permitted to connect to the secondary Aurora cluster on the PostgreSQL port."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids_primary" {
  description = "List of EKS or application security group IDs in the primary region VPC permitted to connect to the primary Aurora cluster."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids_secondary" {
  description = "List of EKS or application security group IDs in the secondary region VPC permitted to connect to the secondary Aurora cluster."
  type        = list(string)
  default     = []
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups and enable point-in-time recovery (7-35 days for production compliance)."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 7 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC time window during which automated backups are created."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC time window during which system maintenance can occur."
  type        = string
  default     = "sun:04:30-sun:05:30"
}

variable "deletion_protection" {
  description = "Whether accidental cluster deletion protection is enabled on the Global Cluster and regional clusters."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip creating a final DB cluster snapshot when destroying the cluster."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Whether cluster and instance modifications are applied immediately rather than during the next maintenance window."
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Whether minor engine upgrades are applied automatically to cluster instances during the maintenance window."
  type        = bool
  default     = true
}

variable "enable_global_write_forwarding" {
  description = "Whether to enable write forwarding on the secondary Aurora cluster so regional readers can forward write transactions to the primary cluster."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Whether to enable Performance Insights on all Aurora PostgreSQL instances (encrypted with regional KMS keys)."
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Retention period in days for Performance Insights data (7 for free tier, 731 for 2 years, or multiples of 31)."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_period == 7 || var.performance_insights_retention_period == 731 || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 731 && var.performance_insights_retention_period % 31 == 0)
    error_message = "performance_insights_retention_period must be 7, 731, or a multiple of 31 between 31 and 731."
  }
}

variable "monitoring_interval" {
  description = "Interval in seconds for RDS Enhanced Monitoring OS metrics collection (0 to disable; 1, 5, 10, 15, 30, or 60)."
  type        = number
  default     = 30

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Retention in days for exported PostgreSQL CloudWatch log groups."
  type        = number
  default     = 90

  validation {
    condition     = contains([7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be a valid CloudWatch Logs retention period (>= 7 days)."
  }
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period in days before a scheduled KMS key deletion takes effect."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}

variable "rpo_max_replication_lag_ms" {
  description = "Maximum acceptable Aurora Global Database cross-region replication lag in milliseconds before triggering a CloudWatch alarm (default 5000ms = 5s)."
  type        = number
  default     = 5000

  validation {
    condition     = var.rpo_max_replication_lag_ms >= 1000 && var.rpo_max_replication_lag_ms <= 60000
    error_message = "rpo_max_replication_lag_ms must be between 1000 (1s) and 60000 (60s)."
  }
}

variable "alarm_actions_primary" {
  description = "List of SNS topic ARNs in the primary region to notify when primary cluster CloudWatch alarms trigger."
  type        = list(string)
  default     = []
}

variable "alarm_actions_secondary" {
  description = "List of SNS topic ARNs in the secondary region to notify when secondary cluster or RPO replication lag CloudWatch alarms trigger."
  type        = list(string)
  default     = []
}

variable "cluster_parameters" {
  description = "Additional custom DB cluster parameter overrides merged on top of the module's hardened PostgreSQL defaults."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "tags" {
  description = "Additional tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
