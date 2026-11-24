variable "service_name" {
  description = "Name of the service that owns this database (e.g., checkout, payments, accounts). Used in resource naming."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_name))
    error_message = "service_name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Target environment / VPC name ('apps-prod' or 'apps-staging')."
  type        = string
  default     = "apps-prod"
}

variable "database_name" {
  description = "Name of the default PostgreSQL database to create. Defaults to service_name with hyphens replaced by underscores."
  type        = string
  default     = null
}

variable "master_username" {
  description = "Master database administrator username."
  type        = string
  default     = "dbadmin"
}

variable "primary_region" {
  description = "Primary AWS region where the writer cluster and initial primary database will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region where the read-replica and disaster-recovery cluster will be deployed."
  type        = string
  default     = "us-west-2"
}

variable "instance_class" {
  description = "RDS DB instance class for Aurora PostgreSQL cluster instances."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Number of Aurora instances to provision in the primary region (minimum 2 recommended for HA writer + reader)."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1
    error_message = "primary_instance_count must be at least 1."
  }
}

variable "secondary_instance_count" {
  description = "Number of Aurora instances to provision in the secondary region (ready to serve read traffic and promote upon failover)."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1
    error_message = "secondary_instance_count must be at least 1."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Defaults to null, which resolves to the latest compatible engine version."
  type        = string
  default     = null
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups for the primary cluster (1 to 35)."
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
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
  description = "Whether deletion protection is enabled on the primary and secondary Aurora clusters."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip creating a final DB snapshot before the cluster is deleted."
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "Amount of time in days to retain Performance Insights data (7 or 731)."
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "performance_insights_retention_period must be either 7 or 731 days."
  }
}

variable "monitoring_interval" {
  description = "Interval in seconds for collecting Enhanced Monitoring metrics (0, 1, 5, 10, 15, 30, or 60)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain exported PostgreSQL logs in CloudWatch Logs."
  type        = number
  default     = 90
}

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to connect to the database clusters on port 5432."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Additional security group IDs in the primary region allowed to connect to the primary cluster."
  type        = list(string)
  default     = []
}

variable "allowed_secondary_security_group_ids" {
  description = "Additional security group IDs in the secondary region allowed to connect to the secondary cluster."
  type        = list(string)
  default     = []
}

variable "app_iam_role_names" {
  description = "IAM role names (e.g., EKS IRSA pod roles) to attach the RDS IAM DB authentication policy to."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
