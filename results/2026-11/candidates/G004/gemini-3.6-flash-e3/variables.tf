variable "name" {
  type        = string
  description = "Name prefix for all resources / service database identifier (e.g. checkout-db)"
}

variable "environment" {
  type        = string
  description = "Deployment environment name (e.g. apps-prod or apps-staging)"
}

variable "primary_vpc_id" {
  type        = string
  description = "VPC ID in the primary AWS region"
}

variable "secondary_vpc_id" {
  type        = string
  description = "VPC ID in the secondary AWS region"
}

variable "primary_region" {
  type        = string
  default     = "us-east-1"
  description = "Primary AWS region for the Aurora PostgreSQL cluster"
}

variable "secondary_region" {
  type        = string
  default     = "us-west-2"
  description = "Secondary AWS region for disaster recovery"
}

variable "engine_version" {
  type        = string
  default     = "15.4"
  description = "Aurora PostgreSQL engine version"
}

variable "database_name" {
  type        = string
  default     = "app"
  description = "Name of the default initial database"
}

variable "master_username" {
  type        = string
  default     = "dbadmin"
  description = "Master DB username for the Aurora cluster"
}

variable "master_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Master DB password. If null, AWS Secrets Manager will manage the password automatically."
}

variable "manage_master_user_password" {
  type        = bool
  default     = true
  description = "Whether to use AWS Secrets Manager for managing the master user password when master_password is null"
}

variable "port" {
  type        = number
  default     = 5432
  description = "Port on which the PostgreSQL database accepts connections"
}

variable "instance_class" {
  type        = string
  default     = "db.r6g.large"
  description = "DB instance class for cluster nodes"
}

variable "primary_instance_count" {
  type        = number
  default     = 2
  description = "Number of database instances to provision in the primary region"
}

variable "secondary_instance_count" {
  type        = number
  default     = 2
  description = "Number of database instances to provision in the secondary region"
}

variable "subnet_tier_tag_key" {
  type        = string
  default     = "tier"
  description = "Tag key used to identify private database subnets in VPCs"
}

variable "subnet_tier_tag_value" {
  type        = string
  default     = "database"
  description = "Tag value used to identify private database subnets in VPCs"
}

variable "primary_subnet_ids" {
  type        = list(string)
  default     = null
  description = "Explicit list of subnet IDs in primary region. If null, subnets will be looked up using primary_vpc_id and subnet tier tag."
}

variable "secondary_subnet_ids" {
  type        = list(string)
  default     = null
  description = "Explicit list of subnet IDs in secondary region. If null, subnets will be looked up using secondary_vpc_id and subnet tier tag."
}

variable "allowed_security_group_ids_primary" {
  type        = list(string)
  default     = []
  description = "List of security group IDs allowed to access the primary Aurora cluster"
}

variable "allowed_cidr_blocks_primary" {
  type        = list(string)
  default     = []
  description = "List of CIDR blocks allowed to access the primary Aurora cluster"
}

variable "allowed_security_group_ids_secondary" {
  type        = list(string)
  default     = []
  description = "List of security group IDs allowed to access the secondary Aurora cluster"
}

variable "allowed_cidr_blocks_secondary" {
  type        = list(string)
  default     = []
  description = "List of CIDR blocks allowed to access the secondary Aurora cluster"
}

variable "allow_vpc_cidr_ingress" {
  type        = bool
  default     = true
  description = "Whether to allow inbound traffic on database port from the primary and secondary VPC CIDR blocks"
}

variable "backup_retention_period" {
  type        = number
  default     = 30
  description = "Backup retention period in days (1-35)"
}

variable "preferred_backup_window" {
  type        = string
  default     = "03:00-04:00"
  description = "Daily time range during which automated backups are created"
}

variable "preferred_maintenance_window" {
  type        = string
  default     = "sun:04:30-sun:05:30"
  description = "Weekly time range during which system maintenance can occur"
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "If true, deletion protection will be enabled on the Aurora global and regional clusters"
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Determines whether a final DB snapshot is created before the cluster is deleted"
}

variable "auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "Indicates that minor engine upgrades will be applied automatically to DB instances during maintenance window"
}

variable "monitoring_interval" {
  type        = number
  default     = 60
  description = "Interval in seconds for Enhanced Monitoring metrics collection (0 to disable, or 1, 5, 10, 15, 30, 60)"
}

variable "performance_insights_enabled" {
  type        = bool
  default     = true
  description = "Specifies whether Performance Insights is enabled"
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  default     = ["postgresql"]
  description = "List of log types to export to CloudWatch Logs"
}

variable "kms_key_arn_primary" {
  type        = string
  default     = null
  description = "ARN of an existing KMS key for storage encryption in primary region. If null, a KMS key is created."
}

variable "kms_key_arn_secondary" {
  type        = string
  default     = null
  description = "ARN of an existing KMS key for storage encryption in secondary region. If null, a KMS key is created."
}

variable "custom_cluster_parameters" {
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default     = []
  description = "List of custom parameters to apply to the RDS cluster parameter groups"
}

variable "custom_db_parameters" {
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default     = []
  description = "List of custom parameters to apply to the RDS DB parameter groups"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Map of tags to assign to all created resources"
}
