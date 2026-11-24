variable "service_name" {
  type        = string
  description = "Name of the service that owns this database (e.g., checkout, users, payment)"
}

variable "environment" {
  type        = string
  description = "Target environment (e.g., apps-prod, apps-staging)"
}

variable "master_password" {
  type        = string
  description = "Master database password"
  sensitive   = true
}

variable "primary_region" {
  type        = string
  description = "AWS region for the primary database cluster"
  default     = "us-east-1"
}

variable "secondary_region" {
  type        = string
  description = "AWS region for the secondary failover database cluster"
  default     = "us-west-2"
}

variable "vpc_name" {
  type        = string
  description = "Optional VPC name override. Defaults to searching VPC by environment tag/name."
  default     = ""
}

variable "database_name" {
  type        = string
  description = "Name of the initial database to create. Defaults to service_name with hyphens converted to underscores."
  default     = null
}

variable "master_username" {
  type        = string
  description = "Master database username"
  default     = "dbadmin"
}

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL engine version"
  default     = "15.4"
}

variable "instance_class" {
  type        = string
  description = "Database instance class for cluster nodes"
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  type        = number
  description = "Number of database instances in the primary cluster"
  default     = 2
}

variable "secondary_instance_count" {
  type        = number
  description = "Number of database instances in the secondary cluster"
  default     = 2
}

variable "backup_retention_period" {
  type        = number
  description = "Number of days to retain automated backups (1-35)"
  default     = 14
}

variable "preferred_backup_window" {
  type        = string
  description = "Daily time range during which automated backups are created (UTC)"
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  type        = string
  description = "Weekly time range during which system maintenance can occur (UTC)"
  default     = "Sun:04:30-Sun:05:30"
}

variable "deletion_protection" {
  type        = bool
  description = "If true, deletion protection will be enabled on the database clusters"
  default     = true
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Determines whether a final DB snapshot is created before the DB cluster is deleted"
  default     = false
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "Additional CIDR blocks allowed to access the database on port 5432"
  default     = []
}

variable "kms_key_arn_primary" {
  type        = string
  description = "Optional existing KMS key ARN for primary region cluster encryption"
  default     = null
}

variable "kms_key_arn_secondary" {
  type        = string
  description = "Optional existing KMS key ARN for secondary region cluster encryption"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all provisioned resources"
  default     = {}
}
