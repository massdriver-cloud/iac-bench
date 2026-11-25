variable "service_name" {
  description = "Name of the customer-facing service owning this database (e.g. checkout, billing). Used in resource naming and tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-32 lowercase alphanumeric characters or hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment. Maps to the network team's VPC (apps-staging or apps-prod)."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["staging", "prod", "apps-staging", "apps-prod"], var.environment)
    error_message = "environment must be one of: staging, prod, apps-staging, apps-prod."
  }
}

variable "database_name" {
  description = "Name of the initial PostgreSQL database to create. Defaults to the service_name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null ? true : can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier (1-63 characters, letters, digits, or underscores, starting with a letter or underscore)."
  }
}

variable "master_username" {
  description = "Master administrator username for the Aurora PostgreSQL cluster."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{1,62}$", var.master_username)) && !contains(["postgres", "rdsadmin", "rds_superuser", "admin", "root"], lower(var.master_username))
    error_message = "master_username must start with a letter, contain only alphanumeric characters or underscores, and not be a reserved PostgreSQL/RDS username."
  }
}

variable "primary_region" {
  description = "Primary AWS region where the writer cluster resides."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-[a-z]+-[0-9]+$", var.primary_region))
    error_message = "primary_region must be a valid US AWS region (e.g. us-east-1, us-east-2, us-west-2)."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region where the Aurora Global Database standby cluster resides for cross-region disaster recovery."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-[a-z]+-[0-9]+$", var.secondary_region))
    error_message = "secondary_region must be a valid US AWS region (e.g. us-west-2, us-east-2) distinct from primary_region."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must be identical across primary and secondary clusters in the global database."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Instance class for provisioned Aurora PostgreSQL instances (or db.serverless when using Aurora Serverless v2)."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = var.instance_class == "db.serverless" || can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be 'db.serverless' or a valid RDS instance class such as 'db.r6g.large'."
  }
}

variable "serverlessv2_scaling_configuration" {
  description = "Optional Aurora Serverless v2 scaling configuration ({ min_capacity, max_capacity } in ACUs). Used when instance_class is db.serverless or to enable mixed provisioned/serverless clusters."
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = null

  validation {
    condition     = var.serverlessv2_scaling_configuration == null ? true : (var.serverlessv2_scaling_configuration.min_capacity >= 0.5 && var.serverlessv2_scaling_configuration.max_capacity >= var.serverlessv2_scaling_configuration.min_capacity && var.serverlessv2_scaling_configuration.max_capacity <= 128)
    error_message = "serverlessv2_scaling_configuration must have 0.5 <= min_capacity <= max_capacity <= 128."
  }
}

variable "primary_instance_count" {
  description = "Number of Aurora instances in the primary region cluster (1 writer + N-1 readers across availability zones; minimum 2 for Multi-AZ high availability)."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be an integer between 2 and 15 to guarantee Multi-AZ high availability."
  }
}

variable "secondary_instance_count" {
  description = "Number of read replica instances in the secondary region cluster (minimum 1 hot standby instance so cross-region failover completes within minutes)."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be an integer between 1 and 15 (headless secondary clusters are not permitted given the minutes-level RTO requirement)."
  }
}

variable "storage_type" {
  description = "Aurora cluster storage configuration. Defaults to aurora-iopt1 (Aurora I/O-Optimized) for predictable production performance."
  type        = string
  default     = "aurora-iopt1"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be 'aurora' or 'aurora-iopt1'."
  }
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups and enable point-in-time recovery (PITR)."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 7 and 35 days for production payment/customer databases."
  }
}

variable "preferred_backup_window" {
  description = "Daily time range (UTC) during which automated backups are created."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly time range (UTC) during which system maintenance can occur."
  type        = string
  default     = "sun:04:30-sun:05:30"
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled on the Global Database and regional clusters."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip creating a final DB cluster snapshot when destroying the database. Should remain false in production."
  type        = bool
  default     = false
}

variable "enable_global_write_forwarding" {
  description = "Enable write forwarding on the secondary region cluster so applications reading from the secondary region can forward occasional writes to the primary region."
  type        = bool
  default     = true
}

variable "allowed_security_group_ids" {
  description = "Optional map of primary and secondary region security group IDs (e.g. EKS node/pod security groups) allowed to connect to PostgreSQL on port 5432. The VPC CIDR is always allowed by default."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "Optional additional CIDR blocks per region allowed to connect to PostgreSQL on port 5432. When empty, ingress is restricted to each region's VPC CIDR block."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "service_iam_role_arns" {
  description = "Optional list of existing EKS service IAM role ARNs to attach the rds-db:connect IAM policy to, in addition to the ready-to-attach IAM policies created by this module."
  type        = list(string)
  default     = []
}

variable "db_users" {
  description = "Additional PostgreSQL database usernames (for EKS services using IAM database authentication) granted rds-db:connect in the generated IAM authentication policy."
  type        = list(string)
  default     = []
}

variable "cluster_parameters" {
  description = "Additional or override DB cluster parameters merged with the module's hardened PostgreSQL defaults."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "monitoring_interval" {
  description = "Interval, in seconds, between points when Enhanced Monitoring metrics are collected for each DB instance."
  type        = number
  default     = 15

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 1, 5, 10, 15, 30, or 60 seconds (Enhanced Monitoring is required for production)."
  }
}

variable "performance_insights_retention_period" {
  description = "Amount of time, in days, to retain Performance Insights data (7 days free tier, multiples of 31 up to 731)."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_period == 7 || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 731 && var.performance_insights_retention_period % 31 == 0)
    error_message = "performance_insights_retention_period must be 7 or a multiple of 31 between 31 and 731."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain exported PostgreSQL audit and server logs in CloudWatch Logs."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be a valid CloudWatch Logs retention period of at least 30 days."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
