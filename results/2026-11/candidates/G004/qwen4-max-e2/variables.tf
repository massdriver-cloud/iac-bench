###############################################################################
# Required: the only things a service team must supply.
###############################################################################

variable "service_name" {
  description = "Short name of the service this database backs (e.g. \"checkout\"). Used to name every resource."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-30 chars, lowercase letters, digits and hyphens, starting with a letter and ending alphanumeric."
  }
}

variable "environment" {
  description = "Environment name. The network team's VPC is discovered by Name tag \"apps-<environment>\" in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\" (must match the network team's VPC naming)."
  }
}

###############################################################################
# Disaster recovery topology. Defaults satisfy the business bar:
# RPO of seconds, RTO of minutes, via Aurora Global Database.
###############################################################################

variable "primary_region" {
  description = "AWS region that normally serves reads and writes."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^us-", var.primary_region))
    error_message = "primary_region must be a US region (data residency requirement)."
  }
}

variable "secondary_region" {
  description = "AWS region that takes over if the primary region fails. Must differ from primary_region."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^us-", var.secondary_region))
    error_message = "secondary_region must be a US region (data residency requirement)."
  }
}

###############################################################################
# Engine / capacity. Defaults are production-safe; tune per service if needed.
###############################################################################

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Both regions and the global cluster run this exact version."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "DB instance class for every instance in both regions. The secondary region is sized to carry full production load after a failover, not scaled down."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Instances in the primary region: one writer plus readers. >= 2 keeps the database available through an in-region instance failure."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 2 and 15 for production high availability."
  }
}

variable "secondary_instance_count" {
  description = "Instances in the secondary region. >= 2 so the region is itself highly available after it is promoted."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15."
  }
}

variable "master_username" {
  description = "Master (admin) username. Its password is generated and rotated by RDS in Secrets Manager; it is never handled by OpenTofu or humans."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{2,15}$", var.master_username)) && !contains(["postgres", "rdsadmin", "admin", "root"], var.master_username)
    error_message = "master_username must be 3-16 chars, start with a letter, and not be a reserved name (postgres, rdsadmin, admin, root)."
  }
}

variable "database_name" {
  description = "Initial database name. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier (letters, digits, underscores; not starting with a digit)."
  }
}

###############################################################################
# Data protection / operations.
###############################################################################

variable "backup_retention_period" {
  description = "Days of automated backups (point-in-time recovery). 35 is the maximum and the production default."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 7 and 35 days for production databases."
  }
}

variable "deletion_protection" {
  description = "Protect the global cluster and both regional clusters from accidental deletion. Leave true for customer/payment data."
  type        = bool
  default     = true
}

variable "kms_deletion_window_in_days" {
  description = "Waiting period before a scheduled KMS key deletion takes effect (guard against losing access to encrypted data)."
  type        = number
  default     = 30

  validation {
    condition     = var.kms_deletion_window_in_days >= 7 && var.kms_deletion_window_in_days <= 30
    error_message = "kms_deletion_window_in_days must be between 7 and 30."
  }
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention in days. 731 (2 years) supports incident forensics on payment workloads."
  type        = number
  default     = 731

  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "performance_insights_retention_period must be 7 or a valid monthly multiple up to 731."
  }
}

variable "enhanced_monitoring_interval" {
  description = "Enhanced OS monitoring granularity in seconds (0 disables)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.enhanced_monitoring_interval)
    error_message = "enhanced_monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of in the maintenance window. Keep false in production unless coordinating a change."
  type        = bool
  default     = false
}

###############################################################################
# Network access.
###############################################################################

variable "allowed_cidr_blocks" {
  description = "Extra CIDR blocks allowed to reach PostgreSQL (in addition to each region's VPC CIDR, which is always allowed so EKS pods can connect). Keep empty unless you have a specific need."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : can(cidrnetmask(c))])
    error_message = "allowed_cidr_blocks must contain valid CIDR blocks."
  }
}

###############################################################################
# Alerting / tagging.
###############################################################################

variable "alert_email" {
  description = "Optional email address subscribed to database alarm notifications in both regions. Wire the output SNS topic ARNs into your paging system for real on-call routing."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
