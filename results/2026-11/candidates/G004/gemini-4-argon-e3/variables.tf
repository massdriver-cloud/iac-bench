variable "service_name" {
  description = "Short, lowercase identifier for the customer-facing service owning this database (e.g. 'checkout', 'payments'). Used to prefix cluster, instance, KMS, IAM, and network resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-30 lowercase alphanumeric characters or hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Target deployment environment. Determines which pre-existing network VPC ('apps-staging' or 'apps-prod') and 'tier = database' subnets are discovered in each region."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod' (corresponding to VPCs 'apps-staging' and 'apps-prod')."
  }
}

variable "primary_region" {
  description = "Primary AWS region hosting the active writer cluster of the Aurora Global Database."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-(east|west)-[1-2]$", var.primary_region))
    error_message = "primary_region must be a valid US AWS region (e.g. us-east-1, us-east-2, us-west-1, us-west-2)."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region hosting the cross-region standby reader cluster of the Aurora Global Database for rapid regional failover and low-RPO write forwarding."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-(east|west)-[1-2]$", var.secondary_region))
    error_message = "secondary_region must be a valid US AWS region (e.g. us-east-1, us-east-2, us-west-1, us-west-2)."
  }
}

variable "database_name" {
  description = "Name of the initial PostgreSQL database created on the primary cluster. Defaults to the service_name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier (1-63 characters, letters, digits, or underscores, starting with a letter or underscore)."
  }
}

variable "master_username" {
  description = "Master administrator username for the Aurora PostgreSQL cluster. The master password is automatically managed and rotated in AWS Secrets Manager."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{2,62}$", var.master_username)) && !contains(["postgres", "rdsadmin", "rdsrepladmin", "admin", "root"], lower(var.master_username))
    error_message = "master_username must start with a letter, contain only alphanumeric characters or underscores (3-63 chars), and not be a reserved PostgreSQL/RDS superuser name."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version prefix or full version string (e.g. '16' or '16.15'). Resolved to the latest matching supported version via aws_rds_engine_version."
  type        = string
  default     = "16"

  validation {
    condition     = can(regex("^(15|16|17)(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must be a supported Aurora PostgreSQL major or minor version (15.x, 16.x, or 17.x)."
  }
}

variable "instance_class" {
  description = "DB instance class for provisioned Aurora PostgreSQL instances, or 'db.serverless' when using Aurora Serverless v2."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = var.instance_class == "db.serverless" || can(regex("^db\\.(r6g|r6i|r7g|r7i|r8g|x2g)\\.(large|xlarge|2xlarge|4xlarge|8xlarge|12xlarge|16xlarge)$", var.instance_class))
    error_message = "instance_class must be 'db.serverless' or a production memory-optimized Aurora instance class (db.r6g, db.r6i, db.r7g, db.r7i, db.r8g, db.x2g)."
  }
}

variable "serverlessv2_scaling_configuration" {
  description = "Optional Aurora Serverless v2 capacity scaling configuration (in ACUs). Used when instance_class is 'db.serverless' or for mixed-capacity clusters."
  type = object({
    min_capacity             = number
    max_capacity             = number
    seconds_until_auto_pause = optional(number)
  })
  default = null

  validation {
    condition     = var.serverlessv2_scaling_configuration == null || (var.serverlessv2_scaling_configuration.min_capacity >= 0.5 && var.serverlessv2_scaling_configuration.max_capacity >= var.serverlessv2_scaling_configuration.min_capacity && var.serverlessv2_scaling_configuration.max_capacity <= 256)
    error_message = "serverlessv2_scaling_configuration must have min_capacity >= 0.5 and min_capacity <= max_capacity <= 256."
  }
}

variable "primary_instance_count" {
  description = "Number of Aurora DB instances in the primary region (1 writer + N-1 in-region Multi-AZ failover readers). Must be at least 2 for production high availability."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be an integer between 2 and 15 to guarantee Multi-AZ high availability in the primary region."
  }
}

variable "secondary_instance_count" {
  description = "Number of Aurora DB instances in the secondary region for the Global Database standby cluster. Must be at least 1 (default 2 for immediate Multi-AZ resilience upon regional failover)."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be an integer between 1 and 15 so the secondary region has warm compute ready for immediate failover."
  }
}

variable "storage_type" {
  description = "Aurora cluster storage configuration ('aurora-iopt1' for Aurora I/O-Optimized or 'aurora' for standard storage)."
  type        = string
  default     = "aurora-iopt1"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be either 'aurora' or 'aurora-iopt1'."
  }
}

variable "port" {
  description = "TCP port on which the Aurora PostgreSQL clusters accept connections."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port must be a valid TCP port between 1150 and 65535."
  }
}

variable "allowed_security_group_ids" {
  description = "Optional map of region ('primary' and/or 'secondary') to lists of EKS worker/pod security group IDs permitted to connect to the database on var.port. The VPC CIDR in each region is always permitted within the private VPC."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "Optional additional CIDR blocks per region ('primary' and/or 'secondary') permitted to connect to the database on var.port. When omitted, ingress defaults to the discovered regional VPC CIDR block."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "app_db_usernames" {
  description = "List of PostgreSQL database usernames used by the service on EKS for IAM database authentication (rds-db:connect). Defaults to the service_name with hyphens replaced by underscores."
  type        = list(string)
  default     = []
}

variable "allowed_iam_principal_arns" {
  description = "Optional list of EKS IAM role ARNs allowed to assume or use the generated rds-db:connect IAM policy."
  type        = list(string)
  default     = []
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups and enable point-in-time recovery (PITR). Minimum 14 days for production customer and payment data."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 14 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 14 and 35 days for payment and customer data compliance."
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
  description = "Whether accidental cluster deletion protection is enabled on the Global Cluster and regional Aurora clusters."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip creating a final DB cluster snapshot before deletion. Should remain false in production."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Whether cluster and instance modifications are applied immediately rather than during the next maintenance window."
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Whether minor engine upgrades (security patches) are applied automatically to DB instances during the maintenance window."
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Interval, in seconds, between points when Enhanced Monitoring metrics are collected for DB instances. Must be 1, 5, 10, 15, 30, or 60."
  type        = number
  default     = 15

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 1, 5, 10, 15, 30, or 60 seconds (Enhanced Monitoring cannot be disabled for production databases)."
  }
}

variable "performance_insights_retention_period" {
  description = "Retention period in days for Performance Insights data (7 days free tier, or 31-731 days paid)."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_period == 7 || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 731)
    error_message = "performance_insights_retention_period must be 7 or between 31 and 731 days."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain exported PostgreSQL audit and instance logs in CloudWatch Logs."
  type        = number
  default     = 90

  validation {
    condition     = contains([14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be a valid CloudWatch Logs retention period of at least 14 days."
  }
}

variable "enable_global_write_forwarding" {
  description = "Whether to enable Aurora Global Database write forwarding on the secondary cluster so applications in the secondary region can forward writes to the primary cluster."
  type        = bool
  default     = true
}

variable "cluster_parameters" {
  description = "Additional or override DB cluster parameter group settings merged onto the hardened production defaults (e.g. rds.force_ssl, pgaudit, statement timeouts)."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "instance_parameters" {
  description = "Additional or override DB instance parameter group settings merged onto the hardened production defaults."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "tags" {
  description = "Additional tags applied to all provisioned resources across both regions."
  type        = map(string)
  default     = {}
}
