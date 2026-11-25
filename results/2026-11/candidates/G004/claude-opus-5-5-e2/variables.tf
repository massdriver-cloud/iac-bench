variable "service_name" {
  description = "Short name of the owning service (e.g. \"checkout\"). Used to name every resource."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-32 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment to deploy into. Selects the network team's VPC named apps-<environment> in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

variable "primary_region" {
  description = "AWS region hosting the writer cluster."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "AWS region hosting the read-only standby cluster that is promoted on regional failure."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-", var.secondary_region))
    error_message = "secondary_region must be a US region."
  }
}

variable "database_name" {
  description = "Name of the initial database. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null
}

variable "master_username" {
  description = "Master (admin) user name. Applications should use IAM database authentication instead of this user."
  type        = string
  default     = "dbadmin"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must support Aurora Global Database."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Instance class for every instance in both regions. Secondary matches primary so it can take full load after failover."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Number of instances in the primary cluster (1 writer + readers). At least 2 for in-region Multi-AZ failover."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2
    error_message = "primary_instance_count must be at least 2 for Multi-AZ high availability."
  }
}

variable "secondary_instance_count" {
  description = "Number of instances in the secondary cluster. At least 2 so the region is Multi-AZ immediately after promotion."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1
    error_message = "secondary_instance_count must be at least 1."
  }
}

variable "allowed_security_group_ids" {
  description = "Security group IDs (e.g. EKS node/pod SGs) allowed to connect on 5432, keyed by \"primary\" / \"secondary\". If both this and allowed_cidr_blocks are empty for a region, the VPC CIDR is allowed."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect on 5432, keyed by \"primary\" / \"secondary\"."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "preferred_backup_window" {
  description = "Daily backup window (UTC)."
  type        = string
  default     = "07:00-08:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window (UTC). Must not overlap the backup window."
  type        = string
  default     = "sun:08:30-sun:09:30"
}

variable "log_retention_days" {
  description = "Retention for the exported PostgreSQL CloudWatch logs."
  type        = number
  default     = 365
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Alarm when cross-region replication lag exceeds this many milliseconds (data-loss exposure on regional failure)."
  type        = number
  default     = 5000
}

variable "alarm_sns_topic_arns" {
  description = "Optional SNS topic ARNs notified by alarms, keyed by \"primary\" / \"secondary\" region."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
