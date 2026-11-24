variable "name" {
  type        = string
  description = "Base name for the database and related resources. Used as an identifier component; keep it short and lowercase."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase alphanumeric or hyphen, and start with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (for example apps-prod or apps-staging). Must match the environment tag/networking layout owned by the network team."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase alphanumeric or hyphen, and start with a letter."
  }
}

variable "primary_region" {
  type        = string
  description = "AWS region that hosts the primary Aurora cluster."
}

variable "secondary_region" {
  type        = string
  description = "AWS region that hosts the Aurora global database secondary cluster."

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must differ from primary_region for a cross-region global database."
  }
}

variable "primary_vpc_id" {
  type        = string
  description = "VPC ID in the primary region that contains the private database subnets."
}

variable "secondary_vpc_id" {
  type        = string
  description = "VPC ID in the secondary region that contains the private database subnets."
}

variable "database_name" {
  type        = string
  description = "PostgreSQL database name to create in the cluster."
}

variable "master_username" {
  type        = string
  default     = "dbadmin"
  description = "Master database username. The password is generated and stored in Secrets Manager."
}

variable "engine_version" {
  type        = string
  default     = "16.4"
  description = "Aurora PostgreSQL engine version."
}

variable "instance_class" {
  type        = string
  default     = "db.r6g.large"
  description = "Instance class for Aurora PostgreSQL database instances."
}

variable "primary_instance_count" {
  type        = number
  default     = 2
  description = "Number of Aurora instances in the primary region. At least two are recommended for production availability."

  validation {
    condition     = var.primary_instance_count >= 1
    error_message = "primary_instance_count must be at least 1."
  }
}

variable "secondary_instance_count" {
  type        = number
  default     = 2
  description = "Number of Aurora instances in the secondary region. At least two are recommended so the promoted secondary itself stays multi-AZ after failover."

  validation {
    condition     = var.secondary_instance_count >= 1
    error_message = "secondary_instance_count must be at least 1."
  }
}

variable "primary_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Optional explicit private database subnet IDs in the primary region. If empty, subnets tagged tier=database in primary_vpc_id are discovered."
}

variable "secondary_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Optional explicit private database subnet IDs in the secondary region. If empty, subnets tagged tier=database in secondary_vpc_id are discovered."
}

variable "database_subnet_tag_value" {
  type        = string
  default     = "database"
  description = "Value of the tier tag used to identify private database subnets when subnet IDs are not supplied."
}

variable "backup_retention_period" {
  type        = number
  default     = 14
  description = "Number of days to retain automated backups. Set to at least the business RPO/retention requirement."
}

variable "preferred_backup_window" {
  type        = string
  default     = "03:00-04:00"
  description = "Daily backup window in UTC for the primary cluster."
}

variable "preferred_maintenance_window" {
  type        = string
  default     = "sun:04:00-sun:05:00"
  description = "Weekly maintenance window in UTC for the primary cluster."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Enable deletion protection for both Aurora clusters and the global cluster."
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Whether to skip creating a final snapshot when a cluster is destroyed. Production modules should leave this false."
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "Whether to apply changes immediately or during the next maintenance window."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "CIDR blocks allowed to reach PostgreSQL on port 5432 (for example the EKS VPC/private CIDRs)."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security group IDs allowed to reach PostgreSQL on port 5432 (for example EKS node or pod security groups)."
}

variable "performance_insights_enabled" {
  type        = bool
  default     = true
  description = "Enable Performance Insights on database instances."
}

variable "monitoring_interval" {
  type        = number
  default     = 60
  description = "Enhanced monitoring collection interval in seconds (0 disables enhanced monitoring)."

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "Enable automatic minor engine version upgrades."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Common tags to apply to resources that support tagging."
}