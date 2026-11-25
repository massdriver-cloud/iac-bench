############################################
# Required: what is specific to the service
############################################

variable "service_name" {
  description = "Short name of the service this database backs (e.g. \"checkout\"). Used to name every resource and, unless overridden, the initial database."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.service_name))
    error_message = "service_name must be 2-31 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment. Selects the network team's VPC (apps-<environment>) in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be one of: staging, prod."
  }
}

############################################
# Regions
############################################

variable "primary_region" {
  description = "Region hosting the writer (primary) cluster."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Region hosting the disaster-recovery (secondary) cluster. Must differ from primary_region."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must be different from primary_region."
  }
}

############################################
# Engine and sizing
############################################

variable "engine_version" {
  description = "Exact Aurora PostgreSQL engine version (major.minor, e.g. \"16.8\"). Pinned so both regions upgrade together through this module rather than drifting independently. Major version must be 14 or newer."
  type        = string
  default     = "16.8"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version)) && tonumber(split(".", var.engine_version)[0]) >= 14
    error_message = "engine_version must be an exact Aurora PostgreSQL version like \"16.8\" with major version 14 or newer."
  }
}

variable "instance_class" {
  description = "DB instance class for every instance in both regions. The secondary must be able to carry the full production load after a failover, so it uses the same class as the primary."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "instance_class must be an RDS instance class such as db.r6g.large."
  }
}

variable "primary_instance_count" {
  description = "Number of instances in the primary cluster (1 writer + N-1 readers across AZs). Minimum 2 so an AZ failure fails over in seconds without leaving the region."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 2 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of instances in the secondary cluster. Minimum 1 so the secondary region can be promoted within minutes (a headless secondary would need instances created first)."
  type        = number
  default     = 1

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15."
  }
}

variable "storage_type" {
  description = "Aurora storage type: \"aurora\" (standard) or \"aurora-iopt1\" (I/O-Optimized; cheaper for I/O-heavy workloads)."
  type        = string
  default     = "aurora"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be \"aurora\" or \"aurora-iopt1\"."
  }
}

############################################
# Database settings
############################################

variable "database_name" {
  description = "Name of the initial database. Defaults to service_name with hyphens replaced by underscores."
  type        = string
  default     = null
}

variable "master_username" {
  description = "Master (break-glass) username. Its password is generated and rotated by RDS in Secrets Manager; applications should use IAM authentication instead."
  type        = string
  default     = "dbadmin"
}

variable "port" {
  description = "TCP port the clusters listen on."
  type        = number
  default     = 5432
}

variable "iam_database_users" {
  description = "PostgreSQL role names that applications connect as using IAM authentication. An IAM policy granting rds-db:connect for these users on both clusters is created for attachment to EKS pod roles. Each role must also be created in PostgreSQL and granted rds_iam."
  type        = list(string)
  default     = ["app"]
}

variable "additional_cluster_parameters" {
  description = "Extra cluster parameter group entries applied in both regions, on top of the module's security/audit baseline."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []
}

############################################
# Resilience and recovery objectives
############################################

variable "rpo_seconds" {
  description = "Recovery point objective enforced by Aurora (rds.global_db_rpo). If replication lag to the secondary exceeds this, Aurora pauses writes on the primary rather than risk losing more than this much data. AWS minimum is 20."
  type        = number
  default     = 20

  validation {
    condition     = var.rpo_seconds >= 20 && var.rpo_seconds <= 2147483647
    error_message = "rpo_seconds must be at least 20 (the Aurora minimum)."
  }
}

variable "backup_retention_days" {
  description = "Automated backup retention in days (7-35)."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35 for production data."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC window for automated backups (hh24:mi-hh24:mi)."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC window for maintenance (ddd:hh24:mi-ddd:hh24:mi)."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Protect the global cluster and both regional clusters from deletion. Leave enabled for anything holding customer data."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of in the next maintenance window. Modifications may cause brief interruptions."
  type        = bool
  default     = false
}

variable "enable_global_write_forwarding" {
  description = "Allow applications in the secondary region to issue writes that Aurora forwards to the primary. Useful if the service runs active/active across regions."
  type        = bool
  default     = false
}

############################################
# Network access
############################################

variable "primary_allowed_security_group_ids" {
  description = "Security groups in the primary region allowed to reach the database (e.g. the EKS node/pod security group)."
  type        = list(string)
  default     = []
}

variable "primary_allowed_cidr_blocks" {
  description = "CIDR blocks in the primary region allowed to reach the database. If neither security groups nor CIDRs are given, the VPC's own CIDR is allowed."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "Security groups in the secondary region allowed to reach the database."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_cidr_blocks" {
  description = "CIDR blocks in the secondary region allowed to reach the database. If neither security groups nor CIDRs are given, the VPC's own CIDR is allowed."
  type        = list(string)
  default     = []
}

############################################
# Observability
############################################

variable "monitoring_interval" {
  description = "Enhanced Monitoring granularity in seconds (0 disables)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention in days (7 is free; 31-731 in multiples of 31 is paid)."
  type        = number
  default     = 7
}

variable "log_retention_days" {
  description = "Retention of PostgreSQL logs in CloudWatch Logs, in days."
  type        = number
  default     = 90
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Alarm when cross-region replication lag exceeds this many milliseconds. Well under rpo_seconds so operators hear about lag before Aurora starts pausing writes."
  type        = number
  default     = 5000
}

variable "alarm_actions" {
  description = "SNS topic ARNs (or other alarm action ARNs) to notify from the module's CloudWatch alarms. ARNs must be in the region of the alarm; the lag alarm lives in the secondary region, the others in the primary region."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

############################################
# Tagging
############################################

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
