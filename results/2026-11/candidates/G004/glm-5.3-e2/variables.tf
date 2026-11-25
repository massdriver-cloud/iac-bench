# -----------------------------------------------------------------------------
# Required inputs - the per-service decisions the platform team makes.
# -----------------------------------------------------------------------------

variable "name" {
  description = <<-EOT
    Short, lowercase name of the service that owns this database, e.g. "checkout".
    Combined with the environment to prefix every resource the module creates,
    e.g. checkout-prod-us-east-1.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 32
    error_message = "name must be 1-32 characters, lowercase alphanumeric, with single hyphens between segments (no leading, trailing or consecutive hyphens)."
  }
}

variable "environment" {
  description = <<-EOT
    Deployment environment: "staging" or "prod". Selects the network team's
    "apps-<environment>" VPC in each region and switches a set of production
    defaults (instance counts, backup retention, deletion protection, final
    snapshots). Everything can still be overridden explicitly.
  EOT
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be one of: staging, prod."
  }
}

variable "database_name" {
  description = <<-EOT
    Name of the initial PostgreSQL database created inside the cluster. Must be
    a valid PostgreSQL identifier (lowercase letters, digits, underscores).
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a lowercase letter and contain only lowercase letters, digits and underscores (max 63 characters)."
  }
}

# -----------------------------------------------------------------------------
# Regions and network placement
# -----------------------------------------------------------------------------

variable "primary_region" {
  description = "AWS region hosting the primary (writable) cluster. Default: us-east-1."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "primary_region must be a US region: us-east-1, us-east-2, us-west-1 or us-west-2."
  }
}

variable "secondary_region" {
  description = "AWS region hosting the standby (readable, failover) cluster. Default: us-west-2."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region) && var.secondary_region != var.primary_region
    error_message = "secondary_region must be a US region and must differ from primary_region."
  }
}

variable "vpc_name" {
  description = <<-EOT
    Name tag of the network team's VPC to place the database in. Defaults to
    "apps-<environment>". Only set this if your VPCs are named differently.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.vpc_name == "" || can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", var.vpc_name))
    error_message = "vpc_name, when set, must be a non-empty VPC name tag value."
  }
}

variable "subnet_ids" {
  description = <<-EOT
    Explicit database subnets per cluster, keyed by role. Set primary and/or
    secondary to bypass tag-based subnet discovery, e.g.
    { primary = ["subnet-...", "subnet-..."], secondary = ["subnet-...", "subnet-..."] }.
    Each non-empty list must contain at least two subnets in distinct
    availability zones that belong to the same VPC.
  EOT
  type        = map(list(string))

  default = {
    primary   = []
    secondary = []
  }

  validation {
    condition     = alltrue([for k in keys(var.subnet_ids) : contains(["primary", "secondary"], k)])
    error_message = "subnet_ids may only contain the keys: primary, secondary."
  }

  validation {
    condition     = alltrue([for v in values(var.subnet_ids) : length(v) == 0 || length(v) >= 2])
    error_message = "Each non-empty subnet_ids list must contain at least two subnets."
  }
}

variable "port" {
  description = "TCP port the clusters listen on."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port must be between 1150 and 65535."
  }
}

# -----------------------------------------------------------------------------
# Database engine and capacity
# -----------------------------------------------------------------------------

variable "engine_version" {
  description = <<-EOT
    Aurora PostgreSQL engine version to run, e.g. "17.9". Leave empty to use the
    default version AWS currently offers for new clusters - the module resolves
    it automatically in the primary region and applies it to both clusters.
    Pin this when you want upgrades to be a deliberate, reviewed change.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.engine_version == "" || can(regex("^\\d+\\.\\d+$", var.engine_version))
    error_message = "engine_version must be empty (use the AWS default) or a full version such as 17.9."
  }
}

variable "master_username" {
  description = <<-EOT
    Master (administrative) role for the cluster. Its password is generated and
    managed by RDS inside Secrets Manager - no password ever lands in OpenTofu
    state. Services must not use this role; they connect with IAM tokens.
  EOT
  type        = string
  default     = "master"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.master_username))
    error_message = "master_username must be a valid PostgreSQL role name (lowercase letters, digits, underscores)."
  }
}

variable "instance_class" {
  description = <<-EOT
    Instance class for the cluster instances in both regions. Any Aurora
    PostgreSQL supported class, e.g. "db.r6g.large". Use "db.serverless" to run
    the clusters on Aurora Serverless v2, with capacity bounds controlled by
    serverless_v2_min_capacity / serverless_v2_max_capacity.
  EOT
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.[a-z0-9][a-z0-9.]*$", var.instance_class))
    error_message = "instance_class must look like a valid DB instance class, e.g. db.r6g.large or db.serverless."
  }
}

variable "instance_count" {
  description = <<-EOT
    Number of instances in the primary region's cluster. Defaults to 2 in prod
    (multi-AZ writer + reader) and 1 in staging. Aurora supports up to 15.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.instance_count == null || (var.instance_count >= 1 && var.instance_count <= 15)
    error_message = "instance_count must be between 1 and 15, or null to use the environment default."
  }
}

variable "secondary_instance_count" {
  description = <<-EOT
    Number of instances in the secondary region's cluster. Defaults to 2 in
    prod (so the region is immediately at full capacity after failover) and 1
    in staging.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.secondary_instance_count == null || (var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15)
    error_message = "secondary_instance_count must be between 1 and 15, or null to use the environment default."
  }
}

variable "serverless_v2_min_capacity" {
  description = "Minimum ACUs per instance when running on Aurora Serverless v2 (instance_class = db.serverless)."
  type        = number
  default     = 0.5

  validation {
    condition     = var.serverless_v2_min_capacity >= 0.5 && var.serverless_v2_min_capacity <= 128
    error_message = "serverless_v2_min_capacity must be between 0.5 and 128 ACUs."
  }
}

variable "serverless_v2_max_capacity" {
  description = "Maximum ACUs per instance when running on Aurora Serverless v2 (instance_class = db.serverless)."
  type        = number
  default     = 32

  validation {
    condition     = var.serverless_v2_max_capacity > var.serverless_v2_min_capacity && var.serverless_v2_max_capacity <= 128
    error_message = "serverless_v2_max_capacity must be greater than serverless_v2_min_capacity and at most 128 ACUs."
  }
}

# -----------------------------------------------------------------------------
# Access control - which clients may reach the database
# -----------------------------------------------------------------------------

variable "allowed_security_group_ids" {
  description = <<-EOT
    Security group IDs (in the primary region's VPC) allowed to reach the
    primary cluster - typically your EKS node or cluster security groups.
    If neither this nor allowed_cidr_blocks is set, the module allows the VPC
    CIDR so that services in the environment VPC can connect out of the box.
  EOT
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = <<-EOT
    Security group IDs (in the secondary region's VPC) allowed to reach the
    secondary cluster. Security group IDs are region-scoped, so the secondary
    region needs its own list.
  EOT
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "IPv4 CIDR blocks allowed to reach the primary cluster."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : can(cidrnetmask(c))])
    error_message = "Each entry in allowed_cidr_blocks must be a valid IPv4 CIDR block."
  }
}

variable "secondary_allowed_cidr_blocks" {
  description = "IPv4 CIDR blocks allowed to reach the secondary cluster."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.secondary_allowed_cidr_blocks : can(cidrnetmask(c))])
    error_message = "Each entry in secondary_allowed_cidr_blocks must be a valid IPv4 CIDR block."
  }
}

# -----------------------------------------------------------------------------
# Data protection and operations (environment-aware defaults)
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Protect the clusters against accidental deletion. Defaults to true in prod, false in staging."
  type        = bool
  default     = null
}

variable "backup_retention_period" {
  description = "Automated backup retention (days) for the primary region. Defaults to 30 in prod, 7 in staging."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retention_period == null || (var.backup_retention_period >= 1 && var.backup_retention_period <= 35)
    error_message = "backup_retention_period must be between 1 and 35 days, or null to use the environment default."
  }
}

variable "secondary_backup_retention_period" {
  description = <<-EOT
    Automated backup retention (days) for the secondary cluster. Aurora global
    secondary clusters do not take their own automated backups - point-in-time
    recovery runs in the region that owns the writer - so this defaults to 0.
    After a failover, backups resume in the promoted region automatically.
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.secondary_backup_retention_period >= 0 && var.secondary_backup_retention_period <= 35
    error_message = "secondary_backup_retention_period must be between 0 and 35 days."
  }
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot when a cluster is destroyed. Defaults to true in staging, false in prod."
  type        = bool
  default     = null
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights on every instance."
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention in days. 7 days is free."
  type        = number
  default     = 7

  validation {
    condition     = contains([7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731], var.performance_insights_retention_period)
    error_message = "performance_insights_retention_period must be one of: 7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, 731 days."
  }
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 disables). Defaults to 60."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60 seconds."
  }
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window for patching, in RDS window syntax."
  type        = string
  default     = "sun:04:00-sun:05:00"

  validation {
    condition     = can(regex("^[a-z]{3}:[0-9]{2}:[0-9]{2}-[a-z]{3}:[0-9]{2}:[0-9]{2}$", var.preferred_maintenance_window))
    error_message = "preferred_maintenance_window must use RDS window syntax, e.g. sun:04:00-sun:05:00."
  }
}

variable "pgaudit_log" {
  description = <<-EOT
    pgaudit event classes to audit on the cluster. Defaults to DDL, role and
    miscellaneous events. Add "read" and/or "write" for a stricter audit trail
    on PCI-scoped databases (at the cost of log volume and write latency).
  EOT
  type        = list(string)
  default     = ["ddl", "role", "misc"]

  validation {
    condition     = length(var.pgaudit_log) > 0 && alltrue([for c in var.pgaudit_log : contains(["read", "write", "function", "role", "ddl", "misc", "misc_set", "all"], c)])
    error_message = "pgaudit_log must be a non-empty list of valid pgaudit classes: read, write, function, role, ddl, misc, misc_set, all."
  }
}

variable "tags" {
  description = "Extra tags to apply to every resource in addition to the module's standard tags."
  type        = map(string)
  default     = {}
}
