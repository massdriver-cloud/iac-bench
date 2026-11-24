# ---------------------------------------------------------------------------
# Required: the only things a service team must decide.
# ---------------------------------------------------------------------------

variable "service_name" {
  description = "Short name of the service that owns this database (e.g. \"checkout\"). Used to name every resource."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,28}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 2-30 characters, lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment. Selects the network team's VPC (apps-staging or apps-prod)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

# ---------------------------------------------------------------------------
# Topology (defaults are the platform standard; override only with good reason).
# ---------------------------------------------------------------------------

variable "primary_region" {
  description = "AWS region that normally serves reads and writes."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "AWS region that takes over during a regional failure. Must differ from primary_region and both must be US regions (data residency)."
  type        = string
  default     = "us-west-2"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must support Aurora Global Database."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "DB instance class for all instances in both regions."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Number of instances in the primary region. 2+ gives a writer plus an in-region hot standby reader."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of warm reader instances in the DR region. At least 1 is required so a regional failover completes in under a minute (a cold secondary takes far longer)."
  type        = number
  default     = 1

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15 (a warm reader is mandatory for the minutes-level RTO)."
  }
}

# ---------------------------------------------------------------------------
# Database identity and access.
# ---------------------------------------------------------------------------

variable "database_name" {
  description = "Name of the initial database created in the cluster."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only letters, digits and underscores (max 63 chars)."
  }
}

variable "master_username" {
  description = "Break-glass administrator username. Its password is generated and rotated by RDS in Secrets Manager; nobody handles it directly."
  type        = string
  default     = "dbadmin"
}

variable "app_db_username" {
  description = "PostgreSQL username the application connects as. The module ships an IAM policy allowing rds-db:connect for this user via IAM database authentication (no password). Create the matching DB user with: CREATE USER <name>; GRANT rds_iam TO <name>;"
  type        = string
  default     = "app"
}

# ---------------------------------------------------------------------------
# Data protection.
# ---------------------------------------------------------------------------

variable "backup_retention_days" {
  description = "Days of automated backups / point-in-time recovery to keep in each region."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35 (production minimum is 7)."
  }
}

variable "deletion_protection" {
  description = "Protect the global database and both clusters from accidental deletion. Keep true for prod."
  type        = bool
  default     = true
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention. 7 days is the free tier; 731 (2 years) is common for long-term forensics."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_days == 7 || (var.performance_insights_retention_days >= 31 && var.performance_insights_retention_days <= 731 && var.performance_insights_retention_days % 31 == 0)
    error_message = "performance_insights_retention_days must be 7 or a multiple of 31 between 31 and 731."
  }
}

variable "log_retention_days" {
  description = "Retention (days) for PostgreSQL engine logs in CloudWatch. 90 days supports incident and payment-data investigations."
  type        = number
  default     = 90
}

# ---------------------------------------------------------------------------
# Network discovery overrides (rarely needed).
# ---------------------------------------------------------------------------

variable "vpc_name_override" {
  description = "Override the Name tag of the VPC to look up. Defaults to apps-<environment> in both regions."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
