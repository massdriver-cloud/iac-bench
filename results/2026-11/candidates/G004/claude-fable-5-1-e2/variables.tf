############################################
# Service-specific inputs (required)
############################################

variable "service_name" {
  description = "Name of the service this database backs (e.g. \"checkout\"). Used to name every resource and, by default, the initial database."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.service_name))
    error_message = "service_name must be 2-31 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment. Selects the network team's VPC (\"apps-<environment>\") in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

############################################
# Topology
############################################

variable "primary_region" {
  description = "AWS region hosting the writer (primary) cluster of the global database."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-", var.primary_region))
    error_message = "primary_region must be a US region (our services only run in US regions)."
  }
}

variable "secondary_region" {
  description = "AWS region hosting the standby (secondary) cluster that is promoted on regional failure."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-", var.secondary_region))
    error_message = "secondary_region must be a US region (our services only run in US regions)."
  }
}

variable "instance_class" {
  description = "Instance class for every DB instance in both regions. Memory-optimised Graviton classes are the production default."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.(r|x)[0-9]", var.instance_class))
    error_message = "instance_class must be a memory-optimised class (db.r* or db.x*); burstable classes are not suitable for production Aurora."
  }
}

variable "primary_instance_count" {
  description = "Number of DB instances in the primary cluster. Two or more gives in-region Multi-AZ failover; Aurora spreads them across AZs."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 2 and 15 (at least two for in-region high availability)."
  }
}

variable "secondary_instance_count" {
  description = "Number of DB instances in the secondary cluster. Keep it at the same size as the primary so the standby region can take full production load the moment it is promoted."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15."
  }
}

variable "enable_global_write_forwarding" {
  description = "Let the secondary cluster accept writes and forward them to the primary. Allows the EKS deployment in the secondary region to use its local cluster endpoint for both reads and writes, so no connection-string change is needed when the secondary is promoted."
  type        = bool
  default     = true
}

############################################
# Engine
############################################

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must be a version that supports Global Database and write forwarding (13.12+, 14.9+, 15.4+, 16.x)."
  type        = string
  default     = "16.4"

  validation {
    condition     = can(regex("^(1[3-9]|[2-9][0-9])\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be a full Aurora PostgreSQL version of the form <major>.<minor>, major 13 or later."
  }
}

variable "database_name" {
  description = "Name of the initial database created in the cluster. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-z_][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid lowercase PostgreSQL identifier."
  }
}

variable "master_username" {
  description = "Master (break-glass) username. Its password is generated and rotated by AWS Secrets Manager; applications should use IAM authentication instead."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.master_username)) && !contains(["admin", "postgres", "rdsadmin", "rds_superuser"], var.master_username)
    error_message = "master_username must be a lowercase identifier and must not be a reserved name (admin, postgres, rdsadmin, rds_superuser)."
  }
}

variable "iam_database_usernames" {
  description = "PostgreSQL role names that application IAM roles may connect as via IAM database authentication. An IAM policy granting rds-db:connect for these roles is created and exported. Each role must also be created in PostgreSQL and granted rds_iam."
  type        = list(string)
  default     = ["app"]

  validation {
    condition     = length(var.iam_database_usernames) > 0 && alltrue([for u in var.iam_database_usernames : can(regex("^[a-z][a-z0-9_]{0,62}$", u))])
    error_message = "iam_database_usernames must contain at least one valid lowercase PostgreSQL role name."
  }
}

############################################
# Network access
############################################

variable "primary_allowed_security_group_ids" {
  description = "Security groups (in the primary region) allowed to reach the database on 5432, e.g. the EKS node/pod security group. If this and allowed_cidr_blocks are both empty, the whole VPC CIDR is allowed."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "Security groups (in the secondary region) allowed to reach the database on 5432. If this and allowed_cidr_blocks are both empty, the whole VPC CIDR is allowed."
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to reach the database on 5432 in both regions (e.g. EKS pod CIDRs). Must be private ranges."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for c in var.allowed_cidr_blocks :
      can(cidrnetmask(c)) && (
        can(regex("^10\\.", c)) ||
        can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", c)) ||
        can(regex("^192\\.168\\.", c)) ||
        can(regex("^100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.", c))
      )
    ])
    error_message = "allowed_cidr_blocks must be valid private (RFC 1918 or CGNAT 100.64/10) IPv4 CIDRs; the database is never exposed publicly."
  }
}

############################################
# Data protection & operations
############################################

variable "backup_retention_days" {
  description = "Automated backup retention in days for both clusters."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35 (production minimum is 7)."
  }
}

variable "deletion_protection" {
  description = "Protect both clusters from deletion. Leave enabled for anything holding customer data; disable only as a deliberate step before decommissioning."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of in the next maintenance window. Leave false for production; set true only when you intend a disruptive change now."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch retention for PostgreSQL/pgaudit logs, in days."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch-supported retention value of at least 30 days."
  }
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention in days (7 is free; 31-731 in multiples of 31 are paid)."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_days == 7 || var.performance_insights_retention_days == 731 || (var.performance_insights_retention_days % 31 == 0 && var.performance_insights_retention_days >= 31 && var.performance_insights_retention_days <= 713)
    error_message = "performance_insights_retention_days must be 7, 731, or a multiple of 31 between 31 and 713."
  }
}

variable "tags" {
  description = "Additional tags applied to every resource in both regions."
  type        = map(string)
  default     = {}
}
