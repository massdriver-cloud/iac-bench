variable "name" {
  description = "Unique lower-case service/database identifier, for example checkout-prod. Used in all resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,37}[a-z0-9]$", var.name))
    error_message = "name must be 2-39 characters, start with a letter, end with a letter or digit, and contain only lower-case letters, digits, and hyphens."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database to create."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier of at most 63 characters."
  }
}

variable "master_username" {
  description = "Administrative database user. RDS generates and manages its password in Secrets Manager; applications should use separate IAM-authenticated users."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]{0,62}$", var.master_username)) && !contains(["postgres", "rdsadmin", "rds_superuser"], lower(var.master_username))
    error_message = "master_username must be a valid non-reserved PostgreSQL identifier of at most 63 characters."
  }
}

variable "primary_region" {
  description = "AWS region containing the initial writer."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-[a-z]+-[0-9]+$", var.primary_region))
    error_message = "primary_region must be a US AWS region such as us-east-1 or us-west-2."
  }
}

variable "secondary_region" {
  description = "AWS region containing the standby global-cluster member."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-[a-z]+-[0-9]+$", var.secondary_region)) && var.secondary_region != var.primary_region
    error_message = "secondary_region must be a US AWS region different from primary_region."
  }
}

variable "primary_vpc_id" {
  description = "ID of the network team's environment VPC in the primary region."
  type        = string
}

variable "secondary_vpc_id" {
  description = "ID of the network team's environment VPC in the secondary region."
  type        = string
}

variable "primary_db_subnet_ids" {
  description = "Optional explicit private database subnet IDs in the primary VPC. If null, subnets tagged tier=database are discovered in primary_vpc_id."
  type        = list(string)
  default     = null

  validation {
    condition     = var.primary_db_subnet_ids == null || length(distinct(var.primary_db_subnet_ids)) >= 2
    error_message = "Specify at least two distinct primary database subnets in different Availability Zones, or null to discover them."
  }
}

variable "secondary_db_subnet_ids" {
  description = "Optional explicit private database subnet IDs in the secondary VPC. If null, subnets tagged tier=database are discovered in secondary_vpc_id."
  type        = list(string)
  default     = null

  validation {
    condition     = var.secondary_db_subnet_ids == null || length(distinct(var.secondary_db_subnet_ids)) >= 2
    error_message = "Specify at least two distinct secondary database subnets in different Availability Zones, or null to discover them."
  }
}

variable "primary_application_security_group_ids" {
  description = "Security groups attached to EKS workloads in the primary VPC that may connect to PostgreSQL."
  type        = list(string)
  default     = []
}

variable "secondary_application_security_group_ids" {
  description = "Security groups attached to EKS workloads in the secondary VPC that may connect to PostgreSQL after recovery."
  type        = list(string)
  default     = []
}

variable "primary_application_cidr_blocks" {
  description = "Optional private IPv4 CIDRs in the primary VPC that may connect to PostgreSQL. Prefer security-group sources."
  type        = list(string)
  default     = []
}

variable "secondary_application_cidr_blocks" {
  description = "Optional private IPv4 CIDRs in the secondary VPC that may connect to PostgreSQL. Prefer security-group sources."
  type        = list(string)
  default     = []
}

variable "instance_class" {
  description = "Aurora instance class used in both regions. Matching capacity avoids replication lag during and after failover."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Instances in the primary cluster. At least two are required for in-region high availability."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be a whole number between 2 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Instances in the secondary cluster. At least two preserve high availability immediately after promotion."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 2 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be a whole number between 2 and 15."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. The major version determines the parameter-group family."
  type        = string
  default     = "16.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version)) && tonumber(split(".", var.engine_version)[0]) >= 13
    error_message = "engine_version must be a full major.minor Aurora PostgreSQL version, major version 13 or newer."
  }
}

variable "backup_retention_period" {
  description = "Automated backup retention in days. Production defaults to the Aurora maximum."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period must be a whole number from 1 to 35."
  }
}

variable "preferred_backup_window" {
  description = "UTC daily automated-backup window in hh24:mi-hh24:mi format."
  type        = string
  default     = "07:00-08:00"
}

variable "preferred_maintenance_window" {
  description = "UTC weekly maintenance window, for example sun:08:00-sun:09:00."
  type        = string
  default     = "sun:08:00-sun:09:00"
}

variable "deletion_protection" {
  description = "Protect the global cluster and both regional clusters from deletion. Disable deliberately before decommissioning."
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "CloudWatch retention for exported PostgreSQL logs."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a CloudWatch Logs supported retention period."
  }
}

variable "alarm_email_endpoints" {
  description = "Email addresses subscribed to both regional alert topics. Empty is allowed when topics are integrated elsewhere via their outputs."
  type        = list(string)
  default     = []
}

variable "rpo_alarm_threshold_seconds" {
  description = "Alarm when the secondary global-cluster RPO lag exceeds this many seconds."
  type        = number
  default     = 5

  validation {
    condition     = var.rpo_alarm_threshold_seconds > 0 && var.rpo_alarm_threshold_seconds <= 60
    error_message = "rpo_alarm_threshold_seconds must be greater than 0 and no more than 60."
  }
}

variable "tags" {
  description = "Additional tags applied to all taggable resources."
  type        = map(string)
  default     = {}
}
