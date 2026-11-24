variable "name" {
  description = "Service name. Used to name the global cluster, clusters, instances and supporting resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment. Selects the network team's VPC in each region (apps-staging or apps-prod)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups (e.g. the EKS node/pod security groups) allowed to connect to PostgreSQL, per region. Security group IDs are regional, so each region has its own list."
  type = object({
    primary   = list(string)
    secondary = list(string)
  })

  validation {
    condition = alltrue([
      for id in concat(var.allowed_security_group_ids.primary, var.allowed_security_group_ids.secondary) :
      can(regex("^sg-[0-9a-f]+$", id))
    ])
    error_message = "All entries must be security group IDs (sg-...)."
  }

  validation {
    condition     = length(var.allowed_security_group_ids.primary) > 0 && length(var.allowed_security_group_ids.secondary) > 0
    error_message = "At least one client security group is required in each region, otherwise the database is unreachable after a regional failover."
  }
}

variable "primary_region" {
  description = "Region initially hosting the writer."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Disaster recovery region holding the global database's secondary cluster."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must differ from primary_region."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (must support Aurora Global Database)."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Instance class for every instance in both regions. Kept identical so a promoted region has the same capacity."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.(r|x)[0-9]", var.instance_class))
    error_message = "Use a memory-optimized class (db.r* or db.x*); burstable classes are unsuitable for production global databases."
  }
}

variable "instances_per_region" {
  description = "Number of instances in each region (one writer/primary plus readers). At least 2 so each region survives an AZ or instance failure."
  type        = number
  default     = 2

  validation {
    condition     = var.instances_per_region >= 2 && var.instances_per_region <= 15
    error_message = "instances_per_region must be between 2 and 15."
  }
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "app"
}

variable "backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "deletion_protection" {
  description = "Protect the clusters from accidental deletion."
  type        = bool
  default     = true
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Alarm when cross-region replication lag exceeds this many milliseconds (the RPO budget)."
  type        = number
  default     = 5000
}

variable "alarm_actions" {
  description = "ARNs (in the secondary region, e.g. an SNS topic) notified when the replication lag alarm fires."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
