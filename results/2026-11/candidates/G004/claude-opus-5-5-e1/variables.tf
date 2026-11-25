variable "service_name" {
  description = "Name of the service that owns this database. Used to name every resource (e.g. \"checkout\")."
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
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "primary_region" {
  description = "AWS region hosting the writer cluster of the global database."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "AWS region hosting the standby (headless-capable, failover target) cluster of the global database."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must differ from primary_region."
  }
}

variable "database_name" {
  description = "Name of the initial database created in the cluster. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null
}

variable "master_username" {
  description = "Master (break-glass) username. Applications should connect with IAM database authentication instead."
  type        = string
  default     = "dbadmin"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must be a version that supports Aurora Global Database."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Instance class used for every instance in both regions (the secondary must be able to take the full write load after failover)."
  type        = string
  default     = "db.r6g.large"
}

variable "instances_per_region" {
  description = "Number of instances per regional cluster. 2+ gives a writer and an in-region failover reader in separate AZs."
  type        = number
  default     = 2

  validation {
    condition     = var.instances_per_region >= 2
    error_message = "instances_per_region must be at least 2 for production high availability."
  }
}

variable "backup_retention_days" {
  description = "Automated backup retention in days (1-35)."
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
  default     = "sun:09:00-sun:10:00"
}

variable "allowed_security_group_ids" {
  description = "Security groups (e.g. EKS node/pod security groups) allowed to connect on 5432, keyed by \"primary\" / \"secondary\" region."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to connect on 5432, keyed by region role. When both this and allowed_security_group_ids are empty for a region, the VPC's own CIDR is allowed."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "iam_db_users" {
  description = "Database user names that application IAM roles may authenticate as via IAM database authentication. An IAM policy granting rds-db:connect for these users on both clusters is created."
  type        = list(string)
  default     = []
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on cluster deletion. Keep false for anything holding real data."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
