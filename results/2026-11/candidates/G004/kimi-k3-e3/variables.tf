# -----------------------------------------------------------------------------
# Per-service inputs - the platform team sets these for each database.
# Everything else is an opinionated module default they should rarely touch.
# -----------------------------------------------------------------------------

variable "name" {
  description = "Service/database name; base for every identifier (global cluster '<name>-<environment>', regional clusters '<name>-<environment>-primary|secondary'). Must be unique per environment in the AWS account."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,28}[a-z0-9]$", var.name))
    error_message = "name must be 2-30 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment this database serves. Selects the network team's VPC (apps-staging or apps-prod) in both regions."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\" - those are the VPCs the network team provides."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database created in the cluster."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier (letter, then letters/digits/underscores, max 63 characters)."
  }
}

variable "primary_region" {
  description = "AWS region hosting the read/write cluster."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "AWS region hosting the standby read-only cluster (the DR target). Must differ from primary_region."
  type        = string
  default     = "us-west-2"
}

variable "vpc_name" {
  description = "Override for the VPC 'Name' tag to look up. Defaults to apps-<environment>, matching the network team's convention."
  type        = string
  default     = null
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach PostgreSQL, per region (typically the EKS node/pod security groups in that region's VPC)."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach PostgreSQL, per region (e.g. pod CIDRs when the CNI assigns pod IPs directly). Prefer security groups where possible."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

# -----------------------------------------------------------------------------
# Sizing and engine
# -----------------------------------------------------------------------------

variable "engine_version" {
  description = "Aurora PostgreSQL engine version for the global cluster and every regional cluster. Pinned deliberately: upgrades are a planned operation."
  type        = string
  default     = "16.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be '<major>.<minor>', e.g. \"16.4\"."
  }
}

variable "instance_class" {
  description = "Instance class for every Aurora instance in both regions. Memory-optimized classes are the right default for production databases."
  type        = string
  default     = "db.r7g.large"

  validation {
    condition     = can(regex("^db\\.", var.instance_class))
    error_message = "instance_class must be an RDS instance class, e.g. \"db.r7g.large\"."
  }
}

variable "primary_instance_count" {
  description = "Instances in the primary cluster: 1 writer + (n-1) readers spread across AZs. Use at least 2 so an in-region failover does not take the service down."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Instances in the secondary (DR) cluster. At least 1 running instance is required for the minutes-level recovery objective: a standby must already be serving to accept a switchover immediately."
  type        = number
  default     = 1

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15."
  }
}

variable "storage_type" {
  description = "Aurora storage type: \"aurora\" (standard) or \"aurora-iopt1\" (I/O-Optimized, usually cheaper for I/O-heavy production workloads)."
  type        = string
  default     = "aurora"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be \"aurora\" or \"aurora-iopt1\"."
  }
}

# -----------------------------------------------------------------------------
# Module-owned guardrails - override only when a service genuinely needs it
# -----------------------------------------------------------------------------

variable "port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}

variable "master_username" {
  description = "Master (break-glass / DBA) username. Its password is generated by RDS and stored in Secrets Manager; applications authenticate with IAM instead."
  type        = string
  default     = "dbadmin"
}

variable "primary_kms_key_arn" {
  description = "Existing KMS key ARN for encryption at rest in the primary region. Null (default) lets the module create and manage a dedicated key."
  type        = string
  default     = null
}

variable "secondary_kms_key_arn" {
  description = "Existing KMS key ARN for encryption at rest in the secondary region. Null (default) lets the module create and manage a dedicated key."
  type        = string
  default     = null
}

variable "backup_retention_period" {
  description = "Days of automated backups / point-in-time recovery. 35 is the Aurora maximum and the right default for customer and payment data."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "backup_window" {
  description = "Daily automated backup window (UTC), 'hh24:mi-hh24:mi'."
  type        = string
  default     = "02:00-03:00"
}

variable "maintenance_window" {
  description = "Weekly maintenance window (UTC), 'ddd:hh24:mi-ddd:hh24:mi'. Must not overlap the backup window."
  type        = string
  default     = "sun:03:30-sun:04:30"
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the clusters. Keep true for production; destroying requires explicitly setting it to false first."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot when a cluster is destroyed. Keep false for production data."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply cluster modifications immediately instead of during the maintenance window. Keep false for production."
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Let AWS auto-upgrade the engine minor version. Off by default: engine versions are pinned and upgraded deliberately."
  type        = bool
  default     = false
}

variable "cloudwatch_log_exports" {
  description = "PostgreSQL log types exported to CloudWatch Logs (auditability for customer/payment data)."
  type        = list(string)
  default     = ["postgresql"]
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention in days: 7 (free tier) or 731."
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period)
    error_message = "performance_insights_retention_period must be 7 or 731."
  }
}

variable "monitoring_interval" {
  description = "Enhanced monitoring granularity in seconds (0 disables)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "cpu_alarm_threshold_percent" {
  description = "CPU utilization percentage that triggers the per-instance alarm."
  type        = number
  default     = 85
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Alarm threshold for cross-region replication lag in milliseconds. This metric is the RPO guardrail: the business allows only a few seconds of data loss."
  type        = number
  default     = 10000
}

variable "tags" {
  description = "Extra tags applied to every resource (on top of the module's platform:* tags)."
  type        = map(string)
  default     = {}
}
