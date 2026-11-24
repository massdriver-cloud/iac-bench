variable "name" {
  description = "Short, unique service/database name used in resource identifiers. Use lowercase letters, digits, and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name))
    error_message = "name must be 2-24 characters, start with a letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "database_name" {
  description = "Name of the initial PostgreSQL database."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid unquoted PostgreSQL identifier of at most 63 characters."
  }
}

variable "primary_region" {
  description = "AWS Region for the writer cluster."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "AWS Region for the continuously replicated disaster-recovery cluster. Must differ from primary_region."
  type        = string
  default     = "us-west-2"
}

variable "primary_vpc_id" {
  description = "ID of the network team's VPC in the primary Region."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-fA-F]+$", var.primary_vpc_id))
    error_message = "primary_vpc_id must be a VPC ID."
  }
}

variable "secondary_vpc_id" {
  description = "ID of the network team's VPC in the secondary Region."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-fA-F]+$", var.secondary_vpc_id))
    error_message = "secondary_vpc_id must be a VPC ID."
  }
}

variable "primary_db_subnet_ids" {
  description = "Optional explicit primary-Region database subnet IDs. If null, subnets in primary_vpc_id tagged tier=database are discovered."
  type        = list(string)
  default     = null

  validation {
    condition     = var.primary_db_subnet_ids == null || length(distinct(var.primary_db_subnet_ids)) >= 2
    error_message = "primary_db_subnet_ids must be null or contain at least two distinct subnet IDs in different Availability Zones."
  }
}

variable "secondary_db_subnet_ids" {
  description = "Optional explicit secondary-Region database subnet IDs. If null, subnets in secondary_vpc_id tagged tier=database are discovered."
  type        = list(string)
  default     = null

  validation {
    condition     = var.secondary_db_subnet_ids == null || length(distinct(var.secondary_db_subnet_ids)) >= 2
    error_message = "secondary_db_subnet_ids must be null or contain at least two distinct subnet IDs in different Availability Zones."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version used by both Regions. The major version determines the parameter-group family."
  type        = string
  default     = "16.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be an explicit major.minor Aurora PostgreSQL version, for example 16.4."
  }
}

variable "instance_class" {
  description = "Provisioned Aurora instance class used in both Regions."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Number of instances in the primary cluster. At least two are required for Multi-AZ availability."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be a whole number from 2 through 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of reader instances in the secondary cluster. At least one is required so a promoted Region can serve immediately."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be a whole number from 1 through 15."
  }
}

variable "master_username" {
  description = "Administrative database user. Its password is generated and managed by RDS in Secrets Manager."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]{0,62}$", var.master_username)) && !contains(["postgres", "rdsadmin", "rds_superuser"], lower(var.master_username))
    error_message = "master_username must be a valid non-reserved PostgreSQL identifier."
  }
}

variable "database_port" {
  description = "PostgreSQL listener port."
  type        = number
  default     = 5432

  validation {
    condition     = var.database_port >= 1024 && var.database_port <= 65535 && floor(var.database_port) == var.database_port
    error_message = "database_port must be a whole number from 1024 through 65535."
  }
}

variable "primary_allowed_security_group_ids" {
  description = "EKS/application security-group IDs allowed to reach PostgreSQL in the primary Region."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "EKS/application security-group IDs allowed to reach PostgreSQL in the secondary Region."
  type        = list(string)
  default     = []
}

variable "primary_allowed_cidr_blocks" {
  description = "Additional private IPv4/IPv6 CIDRs allowed to reach PostgreSQL in the primary Region. Prefer security groups."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.primary_allowed_cidr_blocks :
      can(cidrhost(cidr, 0)) && !contains(["0.0.0.0/0", "::/0"], cidr)
    ])
    error_message = "primary_allowed_cidr_blocks must contain valid, non-unrestricted private CIDRs."
  }
}

variable "secondary_allowed_cidr_blocks" {
  description = "Additional private IPv4/IPv6 CIDRs allowed to reach PostgreSQL in the secondary Region. Prefer security groups."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.secondary_allowed_cidr_blocks :
      can(cidrhost(cidr, 0)) && !contains(["0.0.0.0/0", "::/0"], cidr)
    ])
    error_message = "secondary_allowed_cidr_blocks must contain valid, non-unrestricted private CIDRs."
  }
}

variable "iam_database_users" {
  description = "PostgreSQL users authorized for IAM authentication. Create each user and grant rds_iam in PostgreSQL; see README.md."
  type        = list(string)
  default     = ["app"]

  validation {
    condition = alltrue([
      for user in var.iam_database_users : can(regex("^[A-Za-z_][A-Za-z0-9_]{0,62}$", user))
    ])
    error_message = "Each IAM database user must be a valid unquoted PostgreSQL identifier of at most 63 characters."
  }
}

variable "service_iam_role_names" {
  description = "Optional EKS service IAM role names to which the generated rds-db:connect policy is attached. Roles are not created by this module."
  type        = list(string)
  default     = []
}

variable "backup_retention_period" {
  description = "Automated backup retention in days for each Aurora cluster."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period must be a whole number from 1 through 35."
  }
}

variable "preferred_backup_window" {
  description = "UTC automated backup window in hh24:mi-hh24:mi format."
  type        = string
  default     = "06:00-07:00"
}

variable "preferred_maintenance_window" {
  description = "UTC maintenance window in ddd:hh24:mi-ddd:hh24:mi format. Keep it outside the backup window."
  type        = string
  default     = "sun:07:00-sun:08:00"
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the global cluster and both regional clusters."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final cluster snapshots on destroy. Keep false for production data."
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "Retention for exported PostgreSQL logs in CloudWatch Logs."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a retention value supported by CloudWatch Logs."
  }
}

variable "rpo_lag_alarm_threshold_seconds" {
  description = "Alarm threshold for Aurora global RPO lag. This is an alert threshold, not a substitute for testing recovery."
  type        = number
  default     = 5

  validation {
    condition     = var.rpo_lag_alarm_threshold_seconds > 0
    error_message = "rpo_lag_alarm_threshold_seconds must be greater than zero."
  }
}

variable "primary_alarm_action_arns" {
  description = "Alarm/OK action ARNs for alarms in the primary Region, normally a same-Region SNS topic."
  type        = list(string)
  default     = []
}

variable "secondary_alarm_action_arns" {
  description = "Alarm/OK action ARNs for alarms in the secondary Region, normally a same-Region SNS topic."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to all taggable resources (for example Environment=apps-prod and Owner=platform)."
  type        = map(string)
  default     = {}
}
