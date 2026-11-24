variable "service_name" {
  description = "Name of the service this database belongs to. Used to build deterministic resource identifiers and tags."
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.service_name) >= 2 &&
      length(var.service_name) <= 40 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.service_name)) &&
      !can(regex("--|-$", var.service_name))
    )
    error_message = "service_name must be 2-40 characters, start with a letter, contain only letters, digits, and hyphens, and must not end with a hyphen or contain two consecutive hyphens."
  }
}

variable "environment" {
  description = "Environment/VPC name. This must match the Name tag of the VPC that contains the private database subnets in each region (for example apps-staging or apps-prod)."
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.environment) >= 2 &&
      length(var.environment) <= 30 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.environment)) &&
      !can(regex("--|-$", var.environment))
    )
    error_message = "environment must be 2-30 characters, start with a letter, contain only letters, digits, and hyphens, and must not end with a hyphen or contain two consecutive hyphens."
  }
}

variable "primary_region" {
  description = "AWS region for the primary Aurora cluster."
  type        = string
  nullable    = false
}

variable "secondary_region" {
  description = "AWS region for the cross-region secondary Aurora cluster. Must differ from primary_region."
  type        = string
  nullable    = false

  validation {
    condition     = var.primary_region != var.secondary_region
    error_message = "secondary_region must be different from primary_region for an Aurora global database."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name created on the primary cluster."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL database name (start with a letter or underscore, then letters, digits, or underscores)."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "16.4"
}

variable "master_username" {
  description = "Master database username. IAM database authentication is enabled as well."
  type        = string
  default     = "db_admin"

  validation {
    condition     = can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", var.master_username))
    error_message = "master_username must be a valid PostgreSQL user name."
  }
}

variable "port" {
  description = "PostgreSQL listener port."
  type        = number
  default     = 5432
}

variable "instance_class" {
  description = "Aurora instance class for both regions."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Number of instances in the primary cluster. Keep at least 2 for high availability within the primary region."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1
    error_message = "primary_instance_count must be at least 1."
  }
}

variable "secondary_instance_count" {
  description = "Number of instances in the secondary region. Keep at least 1 so the secondary can serve traffic immediately after promotion."
  type        = number
  default     = 1

  validation {
    condition     = var.secondary_instance_count >= 1
    error_message = "secondary_instance_count must be at least 1."
  }
}

variable "backup_retention_period" {
  description = "Backup retention period in days for each regional cluster."
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "UTC daily backup window."
  type        = string
  default     = "06:00-07:00"
}

variable "preferred_maintenance_window" {
  description = "UTC weekly maintenance window."
  type        = string
  default     = "sun:07:00-sun:08:00"
}

variable "enabled_cloudwatch_logs_exports" {
  description = "PostgreSQL logs to export to CloudWatch Logs."
  type        = list(string)
  default     = ["postgresql"]
}

variable "allow_vpc_cidr" {
  description = "Automatically allow PostgreSQL inbound traffic from the discovered database VPC CIDR in each region."
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to reach PostgreSQL in both regions."
  type        = list(string)
  default     = []
}

variable "primary_allowed_security_group_ids" {
  description = "Security group IDs allowed to reach PostgreSQL in the primary region (for example EKS node/pod security groups)."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "Security group IDs allowed to reach PostgreSQL in the secondary region."
  type        = list(string)
  default     = []
}

variable "create_kms_key" {
  description = "Create a customer-managed KMS key in each region for database storage encryption. If false, the AWS-managed RDS key is used."
  type        = bool
  default     = true
}

variable "kms_deletion_window_in_days" {
  description = "KMS key deletion window in days."
  type        = number
  default     = 7
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights on every Aurora instance."
  type        = bool
  default     = true
}

variable "auto_minor_version_upgrade" {
  description = "Apply minor engine version upgrades automatically during the maintenance window. Keep false for controlled cross-region upgrades."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply non-windowed changes immediately instead of during the next maintenance window."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip a final snapshot when a cluster is deleted. Production services should normally keep this false."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection on the global database and each regional cluster."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to supported resources."
  type        = map(string)
  default     = {}
}