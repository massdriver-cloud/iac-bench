# ---------------------------------------------------------------------------
# Service-specific inputs (what the platform engineer fills in per service)
# ---------------------------------------------------------------------------

variable "name" {
  description = <<-EOT
    Short service identifier, e.g. "checkout". Used to name every resource
    the module creates. Lowercase letters, digits and hyphens; must start
    with a letter.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}$", var.name))
    error_message = "name must be 2-30 characters, start with a lowercase letter, and contain only lowercase letters, digits and hyphens (it seeds Aurora identifiers, which are limited to 63 characters)."
  }
}

variable "environment" {
  description = <<-EOT
    Deployment environment: "staging" or "prod". Selects the network team's
    VPC for this environment ("apps-<environment>") in each region.
  EOT
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\" (matching the apps-staging / apps-prod VPCs owned by the network team)."
  }
}

# ---------------------------------------------------------------------------
# Sensible defaults — override only when a service genuinely needs to
# ---------------------------------------------------------------------------

variable "database_name" {
  description = <<-EOT
    Name of the initial database created in the primary cluster. Defaults to
    the service name with hyphens replaced by underscores (PostgreSQL
    identifier rules). The secondary region inherits it automatically.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only letters, digits and underscores (max 63 characters)."
  }
}

variable "master_username" {
  description = <<-EOT
    Master database user. This is also the database user EKS workloads
    authenticate as via IAM database authentication (the module publishes an
    IAM policy granting rds-db:connect for exactly this user).
  EOT
  type        = string
  default     = "appuser"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must start with a letter and contain only letters, digits and underscores."
  }
}

variable "primary_region" {
  description = "Region hosting the primary (writer) cluster. Must be one of the two US regions the EKS services run in."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Region hosting the hot standby cluster, used when the primary region fails. Must differ from primary_region."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must be different from primary_region."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version for both regions (kept in lockstep so the global database stays compatible)."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = <<-EOT
    Instance class for every cluster instance, in both regions. The standby
    region mirrors the primary so it can absorb full production load
    immediately after a regional failover.
  EOT
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = <<-EOT
    Instances per cluster (one is the writer, the rest are readers), in each
    region. Kept >= 2 so instances span Availability Zones and a single AZ
    failure never takes the database down. The same count is provisioned in
    the DR region.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 2 && var.instance_count <= 15
    error_message = "instance_count must be at least 2 (multi-AZ is mandatory for these production databases) and at most 15."
  }
}

variable "backup_retention_period" {
  description = "Days of point-in-time recovery retained in each region."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "preferred_backup_window" {
  description = "Daily automated backup window (UTC), applied to both clusters."
  type        = string
  default     = "06:00-08:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window (UTC), applied to both clusters."
  type        = string
  default     = "sun:09:00-sun:11:00"
}

variable "deletion_protection" {
  description = "RDS deletion protection. Leave on for real services; only disable temporarily for tearing down test instantiations."
  type        = bool
  default     = true
}

variable "cluster_parameters" {
  description = <<-EOT
    Aurora PostgreSQL DB *cluster* parameter overrides, applied identically
    in both regions. Defaults enforce TLS and capture connect/disconnect
    events — appropriate for customer and payment data.
  EOT
  type        = map(string)
  default = {
    "rds.force_ssl"      = "1"
    "log_connections"    = "1"
    "log_disconnections" = "1"
  }
}

variable "additional_ingress_cidrs" {
  description = "Extra IPv4 CIDRs allowed to reach PostgreSQL, beyond the environment VPC CIDR (e.g. peered network segments)."
  type        = list(string)
  default     = []
}

variable "vpc_name" {
  description = "Override for the environment VPC name looked up via its Name tag. Defaults to apps-<environment>."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}
