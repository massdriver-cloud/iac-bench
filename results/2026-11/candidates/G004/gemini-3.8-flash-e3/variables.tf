variable "name" {
  description = "Name identifier for the database and related resources (e.g. 'checkout', 'orders')."
  type        = string
}

variable "environment" {
  description = "Target deployment environment (e.g. 'prod' or 'staging'). Automatically resolves VPCs named apps-<environment>."
  type        = string
  default     = "prod"
}

variable "primary_region" {
  description = "Primary AWS region where writer instance and primary cluster reside."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for cross-region disaster recovery Aurora replica cluster."
  type        = string
  default     = "us-west-2"
}

variable "database_name" {
  description = "Initial PostgreSQL database name. If null, defaults to sanitized name."
  type        = string
  default     = null
}

variable "master_username" {
  description = "Master username for PostgreSQL database."
  type        = string
  default     = "dbadmin"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Defaults to null (resolves to available engine version)."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "Instance class for Aurora PostgreSQL database instances."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Number of cluster instances to create in the primary region (1 writer + N-1 readers for Multi-AZ)."
  type        = number
  default     = 2
}

variable "secondary_instance_count" {
  description = "Number of cluster instances to create in the secondary region (read replicas ready for regional failover)."
  type        = number
  default     = 2
}

variable "port" {
  description = "Port on which the database accepts connections."
  type        = number
  default     = 5432
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled on the database clusters."
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Backup retention period in days (customer and payment data standard is >= 30 days)."
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

variable "monitoring_interval" {
  description = "Interval in seconds between points when Enhanced Monitoring metrics are collected (0, 1, 5, 10, 15, 30, 60)."
  type        = number
  default     = 60
}

variable "performance_insights_enabled" {
  description = "Specifies whether Performance Insights is enabled."
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Amount of time in days to retain Performance Insights data (7 or 730)."
  type        = number
  default     = 7
}

variable "auto_minor_version_upgrade" {
  description = "Indicates that minor engine upgrades will be applied automatically during maintenance window."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before the DB cluster is deleted."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain exported CloudWatch audit logs."
  type        = number
  default     = 90
}

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to connect to PostgreSQL port."
  type        = list(string)
  default     = []
}

variable "primary_allowed_security_group_ids" {
  description = "List of security group IDs in primary region allowed to connect to the database."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "List of security group IDs in secondary region allowed to connect to the database."
  type        = list(string)
  default     = []
}

variable "iam_database_users" {
  description = "List of database usernames that EKS IAM roles are allowed to authenticate as via IAM. Default allows any dbuser (*)."
  type        = list(string)
  default     = ["*"]
}

variable "service_role_names" {
  description = "List of IAM role names (e.g. EKS IRSA service roles) to attach the RDS IAM connect policy to."
  type        = list(string)
  default     = []
}

variable "primary_vpc_id" {
  description = "Optional override for primary VPC ID. If null, discovered using tag Name=apps-<environment>."
  type        = string
  default     = null
}

variable "secondary_vpc_id" {
  description = "Optional override for secondary VPC ID. If null, discovered using tag Name=apps-<environment>."
  type        = string
  default     = null
}

variable "primary_subnet_ids" {
  description = "Optional override for primary database subnet IDs. If null, discovered using tag tier=database."
  type        = list(string)
  default     = null
}

variable "secondary_subnet_ids" {
  description = "Optional override for secondary database subnet IDs. If null, discovered using tag tier=database."
  type        = list(string)
  default     = null
}

variable "primary_kms_key_arn" {
  description = "Optional existing KMS key ARN for primary region. If null, a Customer Managed Key with key rotation is created."
  type        = string
  default     = null
}

variable "secondary_kms_key_arn" {
  description = "Optional existing KMS key ARN for secondary region. If null, a Customer Managed Key with key rotation is created."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}
