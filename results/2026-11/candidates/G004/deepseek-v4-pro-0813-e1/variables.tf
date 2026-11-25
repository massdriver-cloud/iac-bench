variable "name" {
  description = "Service/database name. Used as the basis for resource identifiers. Must be lowercase letters, numbers, and hyphens, and must start with a letter."
  type        = string

  validation {
    condition = (
      can(regex("^[a-z0-9]$", var.name)) ||
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    )
    error_message = "name must be lowercase letters, numbers, and hyphens, and must start and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name identifying the VPC/network environment. Expected values: apps-staging or apps-prod."
  type        = string

  validation {
    condition     = contains(["apps-staging", "apps-prod"], var.environment)
    error_message = "environment must be one of: apps-staging, apps-prod."
  }
}

variable "primary_region" {
  description = "AWS region for the primary Aurora cluster."
  type        = string
}

variable "secondary_region" {
  description = "AWS region for the cross-region Aurora global database secondary cluster."
  type        = string

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must be different from primary_region."
  }
}

variable "primary_vpc_id" {
  description = "VPC ID in the primary region where the database subnets live."
  type        = string
}

variable "secondary_vpc_id" {
  description = "VPC ID in the secondary region where the database subnets live."
  type        = string
}

variable "primary_subnet_ids" {
  description = "Private database subnet IDs in the primary region (tagged tier = database). Provide at least two subnets in different availability zones."
  type        = list(string)

  validation {
    condition     = length(var.primary_subnet_ids) >= 2
    error_message = "At least two primary subnets are required for Multi-AZ resilience."
  }
}

variable "secondary_subnet_ids" {
  description = "Private database subnet IDs in the secondary region (tagged tier = database). Provide at least two subnets in different availability zones."
  type        = list(string)

  validation {
    condition     = length(var.secondary_subnet_ids) >= 2
    error_message = "At least two secondary subnets are required for Multi-AZ resilience."
  }
}

variable "primary_vpc_cidr" {
  description = "CIDR block of the primary VPC. Used to allow private, in-VPC PostgreSQL access from EKS."
  type        = string
}

variable "secondary_vpc_cidr" {
  description = "CIDR block of the secondary VPC. Used to allow private, in-VPC PostgreSQL access from EKS."
  type        = string
}

variable "database_name" {
  description = "Name of the application database to create."
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master database username for break-glass administrative access. Applications should authenticate with IAM roles."
  type        = string
  default     = "db_admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must be 1-63 characters, start with a letter, and contain only letters, numbers, and underscores."
  }
}

variable "instance_class" {
  description = "Aurora PostgreSQL DB instance class."
  type        = string
  default     = "db.r6g.large"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. This must be a version valid for Aurora PostgreSQL global databases."
  type        = string
  default     = "16.4"
}

variable "primary_instance_count" {
  description = "Number of DB instances to create in the primary cluster. The first instance is preferred as writer (promotion tier 0)."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of DB instances to create in the secondary cluster. Keep at least two so the failover target is also Multi-AZ."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15."
  }
}

variable "port" {
  description = "PostgreSQL TCP port."
  type        = number
  default     = 5432
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups in the primary region."
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35."
  }
}

variable "preferred_backup_window" {
  description = "UTC daily backup window for the primary cluster."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "UTC weekly maintenance window."
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "enabled_cloudwatch_logs_exports" {
  description = "PostgreSQL logs to export to CloudWatch Logs."
  type        = list(string)
  default     = ["postgresql"]
}

variable "deletion_protection" {
  description = "Protect production clusters from accidental deletion."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip a final snapshot on cluster deletion. Keep false for production data."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights on cluster instances."
  type        = bool
  default     = true
}

variable "auto_minor_version_upgrade" {
  description = "Allow minor version upgrades automatically during the maintenance window."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply modifications immediately rather than during the next maintenance window."
  type        = bool
  default     = false
}

variable "kms_deletion_window_days" {
  description = "Waiting period before customer-managed KMS keys are deleted after key deletion."
  type        = number
  default     = 7

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}