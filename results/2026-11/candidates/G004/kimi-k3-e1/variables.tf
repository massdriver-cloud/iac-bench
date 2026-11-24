# -----------------------------------------------------------------------------
# What the platform engineer fills in per service. Everything else is
# opinionated and owned by this module.
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Unique name for this database, typically the service name (e.g. \"checkout\"). Used as the Aurora global cluster identifier and as the base name for all regional resources."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "name must be 1-63 characters of lowercase letters, digits and hyphens, and must start with a letter."
  }
}

variable "primary_region" {
  type        = string
  description = "AWS region hosting the writer (primary) Aurora cluster, e.g. \"us-east-1\"."
}

variable "secondary_region" {
  type        = string
  description = "AWS region hosting the standby (secondary) Aurora cluster that takes over when the primary region fails, e.g. \"us-west-2\"."
}

# -----------------------------------------------------------------------------
# Engine and topology
# -----------------------------------------------------------------------------

variable "engine_version" {
  type        = string
  default     = "16.4"
  description = "Aurora PostgreSQL engine version. Both regional clusters run this version."
}

variable "database_name" {
  type        = string
  default     = "app"
  description = "Name of the initial database created in the cluster."

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier (letters, digits, underscores; not starting with a digit)."
  }
}

variable "master_username" {
  type        = string
  default     = "dbadmin"
  description = "Master username. The master password is generated and managed by RDS in Secrets Manager; it never appears in configuration or state."

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_]{0,15}$", var.master_username))
    error_message = "master_username must be 1-16 characters of letters, digits and underscores, and must start with a letter or underscore."
  }
}

variable "instance_class" {
  type        = string
  default     = "db.r6g.large"
  description = "Instance class for every cluster instance, in both regions."
}

variable "primary_instance_count" {
  type        = number
  default     = 2
  description = "Number of instances in the primary cluster (one writer plus readers), spread across the AZs of the database subnets."

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 15
    error_message = "primary_instance_count must be between 1 and 15."
  }
}

variable "secondary_instance_count" {
  type        = number
  default     = 1
  description = "Number of instances in the secondary cluster. At least one warm instance is required so the secondary region can start serving within minutes of a switchover."

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15
    error_message = "secondary_instance_count must be between 1 and 15."
  }
}

variable "port" {
  type        = number
  default     = 5432
  description = "Port the clusters listen on."
}

# -----------------------------------------------------------------------------
# Networking. The network team owns one VPC per environment per region and
# pre-creates the private database subnets in it; the module discovers both
# by tag so platform engineers never have to paste subnet IDs around.
# -----------------------------------------------------------------------------

variable "vpc_tags" {
  type        = map(string)
  default     = { Name = "apps-prod" }
  description = "Tags identifying the environment VPC in each region. For staging databases set e.g. { Name = \"apps-staging\" }."

  validation {
    condition     = length(var.vpc_tags) > 0
    error_message = "vpc_tags must not be empty."
  }
}

variable "subnet_tags" {
  type        = map(string)
  default     = { tier = "database" }
  description = "Tags identifying the private database subnets inside the selected VPCs."

  validation {
    condition     = length(var.subnet_tags) > 0
    error_message = "subnet_tags must not be empty."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = null
  description = "CIDR blocks allowed to connect to the database port. When null (the default) the CIDR block of the discovered environment VPC is used, which covers the EKS workloads running there."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security group IDs (e.g. EKS node or pod security groups) allowed to connect to the database port, in addition to any CIDR-based rules."
}

# -----------------------------------------------------------------------------
# Protection, backup and maintenance
# -----------------------------------------------------------------------------

variable "backup_retention_period" {
  type        = number
  default     = 35
  description = "Days automated backups are retained (maximum, given these clusters hold customer and payment data)."

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  type        = string
  default     = "03:00-04:00"
  description = "Daily UTC window for automated backups."
}

variable "preferred_maintenance_window" {
  type        = string
  default     = "sun:04:00-sun:05:00"
  description = "Weekly UTC window for pending maintenance."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Protect the global cluster and both regional clusters from deletion. Leave enabled for production."
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Skip the final snapshot when the primary cluster is destroyed. Keep false for production; the secondary cluster never takes a final snapshot (snapshots belong to the primary)."
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "Apply cluster and instance modifications immediately instead of during the maintenance window."
}

variable "auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "Let RDS upgrade minor engine versions automatically during maintenance windows."
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "monitoring_interval" {
  type        = number
  default     = 60
  description = "Enhanced Monitoring collection interval in seconds for every instance; 0 disables it. When enabled the module creates the required IAM role."

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "performance_insights_retention_period" {
  type        = number
  default     = 7
  description = "Performance Insights retention in days (7 = free tier, 731 = long term). Performance Insights is always enabled and encrypted with the regional KMS key."

  validation {
    condition     = contains([7, 731], var.performance_insights_retention_period) || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 713 && var.performance_insights_retention_period % 31 == 0)
    error_message = "performance_insights_retention_period must be 7, 731, or a multiple of 31 between 31 and 713."
  }
}

variable "cluster_parameters" {
  type        = map(string)
  default     = {}
  description = "Additional Aurora cluster parameter group settings, merged over the module defaults. The defaults enforce SSL (rds.force_ssl = 1); overriding that is possible but discouraged for clusters holding payment data."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource created by this module (via provider default_tags)."
}
