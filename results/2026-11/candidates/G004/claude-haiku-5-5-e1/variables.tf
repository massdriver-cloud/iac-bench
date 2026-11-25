variable "service_name" {
  description = "Name of the service that owns this database, e.g. \"checkout\". Lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-40 chars: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment. Selects the network team's VPC (apps-<environment>) in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "primary_region" {
  description = "Region that hosts the writable primary cluster, e.g. \"us-east-1\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.primary_region))
    error_message = "primary_region must be an AWS region name such as us-east-1."
  }
}

variable "secondary_region" {
  description = "Region that hosts the read-only secondary cluster and is promoted during a regional failover, e.g. \"us-west-2\". Must differ from primary_region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.secondary_region))
    error_message = "secondary_region must be an AWS region name such as us-west-2."
  }
}

variable "database_name" {
  description = "Initial database name. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null ? true : can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only lowercase letters, digits and underscores."
  }
}

variable "master_username" {
  description = "Master database user. The password is generated and stored in Secrets Manager."
  type        = string
  default     = "dbadmin"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Applies to both regions; a global database requires them to match."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Instance class for every Aurora instance in both regions."
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = "Aurora instances per region. Minimum 2 so a single AZ or instance failure does not take the region's writes down."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 2
    error_message = "instance_count must be at least 2."
  }
}

variable "backup_retention_days" {
  description = "Automated backup retention in days (7-35)."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC window for automated backups. Must not overlap preferred_maintenance_window."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC window for maintenance."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Protect the global cluster and both regional clusters from deletion."
  type        = bool
  default     = true
}

variable "kms_deletion_window_days" {
  description = "Waiting period before a regional KMS key is deleted (7-30)."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention in days."
  type        = number
  default     = 7
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Replication lag alarm threshold in milliseconds. This is the RPO monitor; the brief allows only a few seconds of lost writes."
  type        = number
  default     = 5000

  validation {
    condition     = var.replication_lag_alarm_threshold_ms > 0 && var.replication_lag_alarm_threshold_ms <= 30000
    error_message = "replication_lag_alarm_threshold_ms must be between 1 and 30000."
  }
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic ARN for alarm notifications. The topic must live in the secondary region for the replication-lag alarm to deliver."
  type        = string
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "Extra IPv4 CIDRs allowed to reach PostgreSQL on 5432 in both regions. The VPC CIDR is always allowed."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach PostgreSQL on 5432 in each region. Groups must belong to that region's VPC."
  type        = list(string)
  default     = []
}

variable "app_db_users" {
  description = "Database users that application IAM roles will authenticate as with IAM database authentication."
  type        = list(string)
  default     = ["app"]
}

variable "app_iam_role_names" {
  description = "Names of existing service IAM roles (e.g. the EKS IRSA roles) to grant rds-db:connect on app_db_users."
  type        = list(string)
  default     = []
}

variable "additional_tags" {
  description = "Extra tags merged into every resource."
  type        = map(string)
  default     = {}
}
