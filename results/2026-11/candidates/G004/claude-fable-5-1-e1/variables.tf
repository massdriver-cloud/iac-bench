############################################
# Required — what is specific to a service
############################################

variable "service_name" {
  description = "Short name of the service that owns this database (e.g. \"checkout\"). Used as the prefix for every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.service_name))
    error_message = "service_name must be 2-31 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Target environment. Determines which VPC (apps-<environment>) the database is placed in."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

############################################
# Topology
############################################

variable "primary_region" {
  description = "AWS region that hosts the primary (writer) cluster of the global database."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-(east|west)-[0-9]$", var.primary_region))
    error_message = "primary_region must be a US region (us-east-N / us-west-N)."
  }
}

variable "secondary_region" {
  description = "AWS region that hosts the secondary (read-only, failover-ready) cluster of the global database."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-(east|west)-[0-9]$", var.secondary_region))
    error_message = "secondary_region must be a US region (us-east-N / us-west-N)."
  }
}

variable "instance_class" {
  description = "Instance class for every Aurora instance in both regions. Memory-optimised Graviton classes are the sensible default for production PostgreSQL."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "instance_class must be an RDS instance class (db.*)."
  }
}

variable "instances_per_region" {
  description = "Number of Aurora instances in each regional cluster. Minimum 2 (writer + reader in different AZs) so a single-AZ failure never takes the service down."
  type        = number
  default     = 2

  validation {
    condition     = var.instances_per_region >= 2 && var.instances_per_region <= 15
    error_message = "instances_per_region must be between 2 and 15."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must be a version that supports Global Database and write forwarding (14.9+, 15.4+, 16.x). Major version upgrades are performed out-of-band on the global cluster; the module ignores drift on this attribute."
  type        = string
  default     = "16.4"
}

variable "database_name" {
  description = "Name of the initial database created in the cluster. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null
}

variable "master_username" {
  description = "Master (break-glass) username. Its password is generated and rotated by AWS Secrets Manager; applications should use IAM authentication instead."
  type        = string
  default     = "postgres_admin"
}

variable "application_db_users" {
  description = "PostgreSQL role names that applications connect as via IAM authentication. The module produces an IAM policy granting rds-db:connect for these users on both clusters. The roles themselves must be created in PostgreSQL (CREATE ROLE <name> WITH LOGIN; GRANT rds_iam TO <name>;)."
  type        = list(string)
  default     = ["app"]
}

variable "enable_global_write_forwarding" {
  description = "Allow applications in the secondary region to send writes to the secondary cluster, which forwards them to the primary. Lets a single connection string per region work for both reads and writes."
  type        = bool
  default     = true
}

############################################
# Network access
############################################

variable "allowed_cidr_blocks" {
  description = "Per-region CIDR blocks allowed to reach PostgreSQL. When a region's list is empty the whole VPC CIDR of that region is allowed (database subnets are private, so this is in-VPC traffic only)."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_security_group_ids" {
  description = "Per-region security group IDs (e.g. EKS node / pod security groups) allowed to reach PostgreSQL, in addition to allowed_cidr_blocks."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

############################################
# Protection, backup & maintenance
############################################

variable "backup_retention_days" {
  description = "Days of automated backups to keep."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35 for production databases."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC window for automated backups (hh24:mi-hh24:mi)."
  type        = string
  default     = "06:00-07:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC window for maintenance (ddd:hh24:mi-ddd:hh24:mi)."
  type        = string
  default     = "sun:08:00-sun:09:00"
}

variable "deletion_protection" {
  description = "Protect clusters from accidental deletion. Only disable when intentionally decommissioning a database."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of in the next maintenance window. Expect brief disruption when true."
  type        = bool
  default     = false
}

############################################
# Observability
############################################

variable "performance_insights_retention_days" {
  description = "Performance Insights retention. 7 is free; 731 (2 years) is recommended for production troubleshooting."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_days == 7 || var.performance_insights_retention_days == 731 || (var.performance_insights_retention_days % 31 == 0 && var.performance_insights_retention_days <= 731)
    error_message = "performance_insights_retention_days must be 7, 731, or a multiple of 31 up to 731."
  }
}

variable "monitoring_interval_seconds" {
  description = "Enhanced Monitoring granularity in seconds."
  type        = number
  default     = 15

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval_seconds)
    error_message = "monitoring_interval_seconds must be one of 1, 5, 10, 15, 30, 60."
  }
}

variable "log_min_duration_statement_ms" {
  description = "Statements running longer than this (ms) are logged as slow queries. -1 disables."
  type        = number
  default     = 1000
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Alarm when cross-region replication lag exceeds this many milliseconds. This is the amount of writes that would be lost in an unplanned failover, so keep it at the business RPO."
  type        = number
  default     = 5000
}

variable "alarm_actions" {
  description = "ARNs (SNS topics, etc.) notified when a CloudWatch alarm fires or recovers. Topics must live in the same region as the alarm; the module places alarms in both regions so pass per-region topics."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
