variable "service_name" {
  description = "Short name of the service that owns this database (lowercase letters, digits, hyphens). Used in all resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-32 chars, start with a letter, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Environment to deploy into. Selects the network team's VPC named apps-<environment> in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be one of: staging, prod."
  }
}

variable "primary_region" {
  description = "AWS region hosting the writer cluster."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-(east|west)-[0-9]$", var.primary_region))
    error_message = "primary_region must be a US commercial AWS region (e.g. us-east-1)."
  }
}

variable "secondary_region" {
  description = "AWS region hosting the read-only secondary cluster that can be promoted on regional failure. Must differ from primary_region."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-(east|west)-[0-9]$", var.secondary_region))
    error_message = "secondary_region must be a US commercial AWS region (e.g. us-west-2)."
  }
}

variable "database_name" {
  description = "Name of the initial database created in the cluster. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a lowercase letter and contain only lowercase letters, digits and underscores (max 63 chars)."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must be a version supported by Aurora Global Database."
  type        = string
  default     = "16.6"
}

variable "instance_class" {
  description = "Instance class for all cluster instances in both regions. Aurora Global Database requires memory-optimized (db.r*) classes."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.r[0-9]", var.instance_class))
    error_message = "instance_class must be a memory-optimized db.r* class (required for Aurora Global Database)."
  }
}

variable "primary_instance_count" {
  description = "Number of instances (1 writer + N-1 readers) in the primary region. Minimum 2 so an AZ failure fails over within the region."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 2 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of instances in the secondary region. Minimum 1 so promotion does not have to wait for an instance to be provisioned; use 2 for production write capacity after failover."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15."
  }
}

variable "master_username" {
  description = "Master (administrative) username. Applications should use IAM authentication instead."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,15}$", var.master_username)) && !contains(["postgres", "admin", "rdsadmin"], var.master_username)
    error_message = "master_username must be 1-16 lowercase alphanumeric/underscore chars, start with a letter, and not be a reserved name."
  }
}

variable "iam_db_username" {
  description = "PostgreSQL role name that application IAM roles are allowed to connect as using IAM authentication. Create it in the database with `CREATE USER <name>; GRANT rds_iam TO <name>;`. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null
}

variable "app_iam_role_names" {
  description = "Names of existing IAM roles (e.g. EKS IRSA / Pod Identity roles for the service) to grant rds-db:connect as iam_db_username on both clusters."
  type        = list(string)
  default     = []
}

variable "primary_allowed_security_group_ids" {
  description = "Security groups (in the primary region VPC) allowed to connect on port 5432, e.g. EKS node/pod security groups. If empty, the VPC's CIDR blocks are allowed instead."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "Security groups (in the secondary region VPC) allowed to connect on port 5432. If empty, the VPC's CIDR blocks are allowed instead."
  type        = list(string)
  default     = []
}

variable "backup_retention_days" {
  description = "Days of automated backups / point-in-time recovery to retain."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC backup window."
  type        = string
  default     = "07:00-08:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC maintenance window. Must not overlap the backup window."
  type        = string
  default     = "sun:08:30-sun:09:30"
}

variable "deletion_protection" {
  description = "Protect the global cluster and both regional clusters from deletion. Only disable deliberately when decommissioning."
  type        = bool
  default     = true
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Alarm when cross-region replication lag (the effective RPO) exceeds this many milliseconds."
  type        = number
  default     = 5000
}

variable "alarm_sns_topic_arns" {
  description = "Map of region => list of SNS topic ARNs to notify for alarms in that region. Optional."
  type        = map(list(string))
  default     = {}
}

variable "log_retention_days" {
  description = "Retention for PostgreSQL logs exported to CloudWatch Logs."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
