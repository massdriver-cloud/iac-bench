variable "name" {
  description = "Name identifier for the service / database workload. Used as a prefix for all created AWS resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. 'prod' or 'staging'). Used to locate the corresponding VPC and subnets."
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "The environment variable must be either 'prod' or 'staging'."
  }
}

variable "database_name" {
  description = "Name of the default PostgreSQL database to create. Defaults to var.name with hyphens replaced by underscores."
  type        = string
  default     = null
}

variable "master_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "dbadmin"
}

variable "primary_region" {
  description = "Primary AWS region for the Aurora PostgreSQL cluster."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for disaster recovery in the Aurora Global Database."
  type        = string
  default     = "us-west-2"
}

variable "primary_vpc_id" {
  description = "Optional VPC ID for the primary region. If omitted, automatically discovered by tag Name = 'apps-{environment}'."
  type        = string
  default     = null
}

variable "secondary_vpc_id" {
  description = "Optional VPC ID for the secondary region. If omitted, automatically discovered by tag Name = 'apps-{environment}'."
  type        = string
  default     = null
}

variable "primary_database_subnet_ids" {
  description = "Optional list of database subnet IDs in the primary region. If omitted, automatically discovered by tag tier = 'database'."
  type        = list(string)
  default     = null
}

variable "secondary_database_subnet_ids" {
  description = "Optional list of database subnet IDs in the secondary region. If omitted, automatically discovered by tag tier = 'database'."
  type        = list(string)
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks permitted to connect to PostgreSQL in the primary region. Defaults to the primary VPC CIDR block."
  type        = list(string)
  default     = null
}

variable "secondary_allowed_cidr_blocks" {
  description = "List of CIDR blocks permitted to connect to PostgreSQL in the secondary region. Defaults to the secondary VPC CIDR block."
  type        = list(string)
  default     = null
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs permitted to connect to PostgreSQL in the primary region."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "List of security group IDs permitted to connect to PostgreSQL in the secondary region."
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "16.1"
}

variable "parameter_group_family" {
  description = "Aurora PostgreSQL parameter group family. If omitted, derived from the major engine version (e.g. aurora-postgresql16)."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "Database instance class for Aurora instances in the primary region."
  type        = string
  default     = "db.r6g.large"
}

variable "secondary_instance_class" {
  description = "Database instance class for Aurora instances in the secondary region. Defaults to var.instance_class if null."
  type        = string
  default     = null
}

variable "primary_instance_count" {
  description = "Number of database instances in the primary region (1 writer + N-1 readers for local high availability)."
  type        = number
  default     = 2
}

variable "secondary_instance_count" {
  description = "Number of database instances in the secondary region for cross-region disaster recovery."
  type        = number
  default     = 2
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups on the primary cluster (1-35 days)."
  type        = number
  default     = 30
}

variable "preferred_backup_window" {
  description = "Daily time range (in UTC) during which automated backups are created."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly time range (in UTC) during which system maintenance can occur."
  type        = string
  default     = "sun:04:30-sun:05:30"
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled on the global and regional clusters."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip final snapshot before deleting primary cluster. Should remain false in production."
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Interval in seconds between Enhanced Monitoring metric collection points (0, 1, 5, 10, 15, 30, 60)."
  type        = number
  default     = 60
}

variable "performance_insights_retention_period" {
  description = "Retention period in days for Performance Insights data (7 or 731)."
  type        = number
  default     = 7
}

variable "log_retention_in_days" {
  description = "Retention period in days for CloudWatch log groups."
  type        = number
  default     = 90
}

variable "app_iam_role_names" {
  description = "List of IAM role names (e.g. EKS service account IAM roles) to grant rds-db:connect permissions to."
  type        = list(string)
  default     = []
}

variable "replication_lag_threshold_ms" {
  description = "CloudWatch alarm threshold in milliseconds for cross-region replication lag (default 5000ms = 5s)."
  type        = number
  default     = 5000
}

variable "alarm_actions" {
  description = "List of SNS topic ARNs to notify when CloudWatch alarms trigger."
  type        = list(string)
  default     = []
}

variable "primary_kms_key_arn" {
  description = "Optional existing KMS key ARN for primary region. If null, a dedicated customer-managed key is created."
  type        = string
  default     = null
}

variable "secondary_kms_key_arn" {
  description = "Optional existing KMS key ARN for secondary region. If null, a dedicated customer-managed key is created."
  type        = string
  default     = null
}

variable "custom_cluster_parameters" {
  description = "Additional custom parameters to apply to the DB cluster parameter group."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "custom_db_parameters" {
  description = "Additional custom parameters to apply to the DB instance parameter group."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "tags" {
  description = "A map of tags to assign to all resources."
  type        = map(string)
  default     = {}
}
