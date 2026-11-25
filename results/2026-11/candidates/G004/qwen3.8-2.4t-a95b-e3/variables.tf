# ---------------------------------------------------------------------------
# Identity: what the platform team fills in for each service
# ---------------------------------------------------------------------------

variable "name" {
  description = "Short service name, e.g. \"checkout\". Prefixes every resource the module creates and seeds the cluster and global-cluster identifiers."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,23}$", var.name))
    error_message = "name must be 1-24 characters, start with a lowercase letter, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Selects the network team's VPC \"apps-<environment>\" in each region; the platform standardizes on \"staging\" and \"prod\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.environment))
    error_message = "environment must be 1-12 lowercase alphanumeric characters (e.g. \"staging\", \"prod\")."
  }
}

variable "database_name" {
  description = "Logical PostgreSQL database created in the cluster. Defaults to the service name with hyphens mapped to underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only letters, digits and underscores (max 63 characters)."
  }
}

variable "tags" {
  description = "Extra tags merged on top of the module's standard tags (Service, Environment, Component, ManagedBy, DataClass)."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Regions
# ---------------------------------------------------------------------------

variable "primary_region" {
  description = "Region that hosts the writable (primary) Aurora cluster."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Region that hosts the read-only (secondary) Aurora cluster used for cross-region disaster recovery."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must be different from primary_region."
  }
}

# ---------------------------------------------------------------------------
# Engine and sizing
# ---------------------------------------------------------------------------

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must be available in both regions and supported by Aurora Global Database."
  type        = string
  default     = "17.9"
}

variable "instance_class" {
  description = "Instance class for every cluster member (writer and readers, both regions). db.r6g.large is the platform floor for production services."
  type        = string
  default     = "db.r6g.large"
}

variable "instances_per_cluster" {
  description = "Instances per region: 1 writer + (N-1) readers. Keep >= 2 — with a single instance an AZ failure takes the database down instead of failing over."
  type        = number
  default     = 2

  validation {
    condition     = var.instances_per_cluster >= 1 && var.instances_per_cluster <= 15
    error_message = "instances_per_cluster must be between 1 and 15."
  }
}

variable "auto_minor_version_upgrade" {
  description = "Allow Aurora to apply minor engine upgrades automatically in the maintenance window (both regions stay on matching versions)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------

variable "master_username" {
  description = "Master username. The password is generated and managed by RDS in Secrets Manager (see master_credentials_secret_arn output) unless master_password is supplied."
  type        = string
  default     = "postgres"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must start with a letter and contain only letters, digits and underscores."
  }
}

variable "master_password" {
  description = "Bring-your-own master password (e.g. migrating an existing database). Leave null to let RDS generate and manage the password in Secrets Manager — the recommended path."
  type        = string
  default     = null
  sensitive   = true
}

variable "iam_database_auth_enabled" {
  description = "Enable IAM authentication so EKS workloads can connect with short-lived tokens minted from their pod IAM roles instead of static passwords."
  type        = bool
  default     = true
}

variable "port" {
  description = "TCP port the cluster listens on."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "port must be in the range 1024-65535."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach the database port, per region — typically the EKS node or pod security groups of the owning service. Traffic from the environment VPC CIDR is always allowed."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to reach the database port, per region, on top of the environment VPC CIDR."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "cluster_parameters" {
  description = "Extra cluster parameter group settings. rds.force_ssl=1 (TLS-only client connections) is always applied unless explicitly overridden here."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Network discovery
# ---------------------------------------------------------------------------

variable "vpc_name" {
  description = "Value of the Name tag on the VPC the network team owns for this environment. Defaults to \"apps-<environment>\"."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Durability and operations
# ---------------------------------------------------------------------------

variable "backup_retention_days" {
  description = "Days of point-in-time backup retained on the primary cluster. Aurora manages backups for a global database from the primary region."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "preferred_backup_window" {
  description = "Daily UTC window for automated backups (hh24:mi-hh24:mi)."
  type        = string
  default     = "07:00-09:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC window for maintenance (ddd:hh:mm-ddd:hh:mm). Must not overlap the backup window."
  type        = string
  default     = "sun:04:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Block accidental deletion of the global cluster and both regional clusters. Keep true; set false only to intentionally tear down."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights on every instance (7-day retention included)."
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring granularity in seconds; 0 disables it."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be 0, 1, 5, 10, 15, 30 or 60."
  }
}
