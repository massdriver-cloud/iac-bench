###############################################################################
# Service-specific inputs — the only things a platform engineer has to fill
# in. Everything else below has a deliberate, production-safe default.
###############################################################################

variable "service_name" {
  description = "Short, lowercase name of the service that owns this database (e.g. \"checkout\"). Used to derive every resource name in the module."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,22}[a-z0-9])?$", var.service_name))
    error_message = "service_name must be 1-24 characters, start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = <<-DESC
    Deployment environment. The network team owns one apps VPC per environment
    in every region we operate in, named "apps-<environment>" (apps-staging,
    apps-prod), with private database subnets tagged tier=database inside.
    "prod" turns on the production-grade defaults (deletion protection) that
    staging intentionally leaves off.
  DESC
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\" — these are the environments the network team has VPCs for."
  }
}

variable "instance_class" {
  description = "Aurora PostgreSQL instance class used in both regions (e.g. \"db.t4g.medium\" or \"db.r7g.large\"). Sizing is the one thing only the owning service team can decide; everything else has a default."
  type        = string

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be a valid RDS instance class such as db.t4g.medium or db.r7g.large."
  }
}

###############################################################################
# Regional layout
###############################################################################

variable "primary_region" {
  description = "AWS region hosting the primary (writable) cluster. Defaults to our standard US primary."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-\\d+$", var.primary_region))
    error_message = "primary_region must be a valid AWS region name, e.g. us-east-1."
  }
}

variable "secondary_region" {
  description = "AWS region hosting the warm-standby (DR) cluster. Must differ from primary_region; enforced by the module."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-\\d+$", var.secondary_region))
    error_message = "secondary_region must be a valid AWS region name, e.g. us-west-2."
  }
}

variable "primary_vpc_id" {
  description = "Optional override: VPC ID in the primary region, if the network team's Name-tag convention (apps-<environment>) doesn't apply. When unset, the module discovers the VPC by its Name tag."
  type        = string
  default     = null

  validation {
    condition     = var.primary_vpc_id == null || can(regex("^vpc-[0-9a-f]+$", var.primary_vpc_id))
    error_message = "primary_vpc_id must be a VPC ID (vpc-...) or null to discover it by Name tag."
  }
}

variable "secondary_vpc_id" {
  description = "Optional override: VPC ID in the secondary region. When unset, the module discovers the VPC by its Name tag."
  type        = string
  default     = null

  validation {
    condition     = var.secondary_vpc_id == null || can(regex("^vpc-[0-9a-f]+$", var.secondary_vpc_id))
    error_message = "secondary_vpc_id must be a VPC ID (vpc-...) or null to discover it by Name tag."
  }
}

variable "vpc_name" {
  description = "Name tag of the network team's apps VPC, when it doesn't follow the standard \"apps-<environment>\" convention."
  type        = string
  default     = null
}

###############################################################################
# Engine
###############################################################################

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (e.g. \"16.4\"). Changing it upgrades the global database: OpenTofu applies the new version to the global cluster first and then rolls each regional cluster through it, so the two members never drift apart."
  type        = string
  default     = "16.4"

  validation {
    condition     = can(regex("^1[3-7]\\.\\d+$", var.engine_version))
    error_message = "engine_version must be an Aurora PostgreSQL version such as 15.6 or 16.4."
  }
}

variable "database_name" {
  description = "Optional name of a default database created with the cluster. Leave unset (recommended) and let each service's migrations create its own databases, roles, and grants."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[A-Za-z_][A-Za-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid PostgreSQL identifier."
  }
}

variable "master_username" {
  description = "Name of the break-glass master user. RDS generates, stores, and rotates its password in AWS Secrets Manager, so it never appears in OpenTofu state, plans, or CI logs. Services must not use this account — they connect with IAM database authentication."
  type        = string
  default     = "postgres"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,29}$", var.master_username))
    error_message = "master_username must be 1-30 characters — lowercase letters, digits, or underscores, starting with a letter or underscore."
  }
}

variable "port" {
  description = "Port the primary cluster listens on. The DR cluster inherits it through the global database."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port must be between 1150 and 65535 (AWS reserves the ports below 1150 for RDS)."
  }
}

###############################################################################
# Capacity & resilience
###############################################################################

variable "instance_count" {
  description = "Aurora instances in the primary region's cluster. The default of 2 keeps an in-region standby so a single instance failure never interrupts the writer."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 15 && floor(var.instance_count) == var.instance_count
    error_message = "instance_count must be a whole number between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Aurora instances in the DR region's cluster. At least 1 is required — a DR cluster with no instances cannot be promoted to serve traffic. Consider matching the primary's capacity for services that must fail over without degrading."
  type        = number
  default     = 1

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be a whole number between 1 and 15."
  }
}

variable "backup_retention_period" {
  description = "Days of automated backups and point-in-time recovery on the primary cluster (1-35). Note that logical corruption replicates faithfully to the DR region, so PITR is the recovery path of record; use 35 for services with the longest retention obligations."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

variable "deletion_protection" {
  description = "Whether Aurora refuses to delete the clusters. Leave unset (null) for the module default: protection on in prod, off in staging so environments stay tear-down-able. Set true/false to override."
  type        = bool
  default     = null
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot of the primary cluster on destroy. Defaults to true so pipelines and sandboxes destroy cleanly; for prod set false (deletion protection is on there anyway) and provide final_snapshot_identifier."
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Name for the primary cluster's final snapshot, required when skip_final_snapshot = false."
  type        = string
  default     = null
}

###############################################################################
# Security & compliance (these databases hold customer and payment data)
###############################################################################

variable "enable_iam_database_auth" {
  description = "Let services connect with IAM database authentication (rds-db:connect) — the path our EKS services use through their IAM roles — instead of shared passwords. Keep enabled for anything touching customer or payment data."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Optional existing KMS customer-managed key (in the primary region) for cluster storage and the master-user secret. When unset, the module creates a dedicated CMK with annual rotation."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, or null to let the module create one."
  }
}

variable "pgaudit_log_classes" {
  description = "pgAudit statement classes exported to the CloudWatch audit log. The default records writes, DDL, role changes, and utility statements. Add \"read\" when an auditor requires visibility into cardholder-data reads — expect a large increase in log volume."
  type        = list(string)
  default     = ["write", "ddl", "role", "misc"]

  validation {
    condition = length(var.pgaudit_log_classes) > 0 && alltrue([
      for c in var.pgaudit_log_classes :
      contains(["read", "write", "function", "ddl", "role", "misc", "misc_set", "all"], c)
    ])
    error_message = "pgaudit_log_classes may only contain: read, write, function, ddl, role, misc, misc_set, all."
  }
}

variable "log_retention_in_days" {
  description = "CloudWatch retention for the postgres and audit logs each cluster exports. RDS's own auto-created log groups never expire, so the module manages the groups explicitly to bound storage cost and retention."
  type        = number
  default     = 90

  validation {
    condition = contains([
      0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096,
      1827, 2192, 2557, 2922, 3288, 3653,
    ], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a valid CloudWatch Logs retention period (0 = never expire)."
  }
}

###############################################################################
# Observability
###############################################################################

variable "performance_insights_enabled" {
  description = "Enable Performance Insights on every instance. Defaults on: it is the easiest way for a non-specialist to answer \"why is the database slow?\""
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Days to keep Performance Insights data. 7 is included at no charge; longer retention (e.g. 731 for two years) is billed and useful for post-incident forensics."
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring collection interval in seconds: 0 (disabled), 15, 30, or 60."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 15, 30, or 60 seconds."
  }
}

###############################################################################
# Connectivity
###############################################################################

variable "allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to open PostgreSQL connections, applied in both regions (e.g. an inter-region peered network). Access from the local region's apps VPC is always allowed and cannot be turned off."
  type        = list(string)
  default     = []
}

variable "preferred_backup_window" {
  description = "Daily UTC window for automated backups on the primary cluster. Must not overlap the maintenance window."
  type        = string
  default     = "08:00-09:00"

  validation {
    condition     = can(regex("^([01]\\d|2[0-3]):[0-5]\\d-([01]\\d|2[0-3]):[0-5]\\d$", var.preferred_backup_window))
    error_message = "preferred_backup_window must look like \"hh:mm-hh:mm\" in UTC, e.g. 08:00-09:00."
  }
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC window for patching and maintenance, applied to both clusters. Must not overlap preferred_backup_window."
  type        = string
  default     = "sun:09:00-sun:10:00"

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01]\\d|2[0-3]):[0-5]\\d-(mon|tue|wed|thu|fri|sat|sun):([01]\\d|2[0-3]):[0-5]\\d$", var.preferred_maintenance_window))
    error_message = "preferred_maintenance_window must look like \"sun:09:00-sun:10:00\" (UTC)."
  }
}

###############################################################################
# Tags
###############################################################################

variable "tags" {
  description = "Additional tags merged into every resource the module creates."
  type        = map(string)
  default     = {}
}

variable "data_classification" {
  description = "Value of the DataClassification tag applied to all resources. These databases hold customer and payment data, so it defaults to \"confidential\"; adjust if your classification scheme differs."
  type        = string
  default     = "confidential"
}
