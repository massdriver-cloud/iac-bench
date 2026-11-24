# -----------------------------------------------------------------------------
# Required Service-Specific Inputs
# -----------------------------------------------------------------------------

variable "service_name" {
  description = "Name of the customer-facing service owning this database (e.g. 'checkout', 'payments'). Used for resource naming, tagging, and default database/role naming."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,28}[a-z0-9])?$", var.service_name)) && !can(regex("--", var.service_name))
    error_message = "service_name must be 1-30 characters, start with a lowercase letter, end with a lowercase letter or digit, contain only lowercase letters, digits, and single hyphens."
  }
}

variable "environment" {
  description = "Target environment matching the network team's shared VPC convention ('staging' -> apps-staging, 'prod' -> apps-prod)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod' (corresponding to VPCs 'apps-staging' and 'apps-prod')."
  }
}

variable "primary_region" {
  description = "Primary US AWS region hosting the active Aurora PostgreSQL writer cluster (e.g. 'us-east-1')."
  type        = string

  validation {
    condition     = can(regex("^us-(east|west)-[1-9]$", var.primary_region))
    error_message = "primary_region must be a commercial US AWS region (e.g. 'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2')."
  }
}

variable "secondary_region" {
  description = "Secondary US AWS region hosting the warm Aurora Global Database standby cluster for fast regional failover (e.g. 'us-west-2')."
  type        = string

  validation {
    condition     = can(regex("^us-(east|west)-[1-9]$", var.secondary_region)) && var.secondary_region != var.primary_region
    error_message = "secondary_region must be a commercial US AWS region and must differ from primary_region."
  }
}

# -----------------------------------------------------------------------------
# Database Identity & Engine Configuration
# -----------------------------------------------------------------------------

variable "database_name" {
  description = "Initial PostgreSQL database name created in the cluster. Defaults to service_name with hyphens converted to underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a lowercase letter and contain only lowercase letters, digits, and underscores (max 63 chars)."
  }
}

variable "master_username" {
  description = "Master administrative username for break-glass/bootstrap administration (password managed automatically in AWS Secrets Manager). Avoids default 'postgres' username."
  type        = string
  default     = "postgres_admin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{2,62}$", var.master_username)) && !contains(["postgres", "admin", "root", "rdsadmin"], var.master_username)
    error_message = "master_username must be a valid PostgreSQL identifier (3-63 chars) and must not be 'postgres', 'admin', 'root', or 'rdsadmin'."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL major or full engine version (e.g. '16', '16.15', '17'). Resolved via AWS to ensure exact version parity across both regions."
  type        = string
  default     = "16"

  validation {
    condition     = can(regex("^(15|16|17)(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must be a supported Aurora PostgreSQL 15, 16, or 17 version string (e.g. '16' or '16.15')."
  }
}

variable "port" {
  description = "TCP port on which the Aurora PostgreSQL clusters accept connections."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port must be between 1150 and 65535."
  }
}

# -----------------------------------------------------------------------------
# Compute, Capacity & Multi-Region High Availability
# -----------------------------------------------------------------------------

variable "instance_class" {
  description = "DB instance class for cluster instances. Defaults to 'db.serverless' (Aurora Serverless v2) for automatic vertical scaling and warm standby efficiency; may also be set to a provisioned Graviton class such as 'db.r7g.large' or 'db.r8g.large'."
  type        = string
  default     = "db.serverless"

  validation {
    condition     = var.instance_class == "db.serverless" || can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be 'db.serverless' or a valid RDS provisioned DB instance class (e.g. 'db.r7g.large')."
  }
}

variable "serverlessv2_min_capacity" {
  description = "Minimum Aurora Capacity Units (ACUs) when instance_class is 'db.serverless'. Defaults to 2.0 ACUs (>= 0.5 prevents cold auto-pause so failover and queries respond immediately)."
  type        = number
  default     = 2

  validation {
    condition     = var.serverlessv2_min_capacity >= 0.5 && var.serverlessv2_min_capacity <= 256
    error_message = "serverlessv2_min_capacity must be between 0.5 and 256 ACUs (0 ACU auto-pause is disallowed for production failover readiness)."
  }
}

variable "serverlessv2_max_capacity" {
  description = "Maximum Aurora Capacity Units (ACUs) when instance_class is 'db.serverless'."
  type        = number
  default     = 16

  validation {
    condition     = var.serverlessv2_max_capacity >= var.serverlessv2_min_capacity && var.serverlessv2_max_capacity <= 256
    error_message = "serverlessv2_max_capacity must be >= serverlessv2_min_capacity and <= 256 ACUs."
  }
}

variable "primary_instance_count" {
  description = "Number of DB instances in the primary region (1 writer + N-1 Multi-AZ readers). At least 2 is recommended for sub-minute intra-region AZ failover."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1 && var.primary_instance_count <= 15 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be an integer between 1 and 15."
  }
}

variable "secondary_instance_count" {
  description = "Number of warm reader DB instances in the secondary region. Must be >= 1 so regional failover completes within minutes (headless secondary clusters violate RTO) and defaults to 2 so the promoted region is immediately Multi-AZ."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be an integer between 1 and 15 (headless 0-instance secondary clusters cannot meet minute-scale regional RTO)."
  }
}

variable "storage_type" {
  description = "Aurora cluster storage configuration ('aurora-iopt1' for Aurora I/O-Optimized predictable latency/cost, or 'aurora' for standard storage)."
  type        = string
  default     = "aurora-iopt1"

  validation {
    condition     = contains(["aurora", "aurora-iopt1"], var.storage_type)
    error_message = "storage_type must be either 'aurora-iopt1' or 'aurora'."
  }
}

variable "enable_global_write_forwarding" {
  description = "Enable Aurora Global Database write forwarding on the secondary cluster so applications reading locally in the secondary region can forward writes to the primary cluster."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Network Access & IAM Authentication (EKS Integration)
# -----------------------------------------------------------------------------

variable "allowed_security_group_ids" {
  description = "Optional per-region lists of EKS node/pod security group IDs permitted to reach the Aurora PostgreSQL port."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "Optional per-region lists of IPv4 CIDR blocks (e.g. EKS pod/private application subnets) permitted to reach the Aurora PostgreSQL port."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}

  validation {
    condition = alltrue([
      for cidr in concat(var.allowed_cidr_blocks.primary, var.allowed_cidr_blocks.secondary) :
      can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0"
    ])
    error_message = "All allowed_cidr_blocks must be valid IPv4 CIDRs and must never be 0.0.0.0/0."
  }
}

variable "allow_vpc_cidr_ingress" {
  description = "Allow TCP connections on the database port from within each region's environment VPC CIDR ('apps-staging' or 'apps-prod'). When null (default), automatically enabled only when no explicit allowed_security_group_ids or allowed_cidr_blocks are provided for that region."
  type        = bool
  default     = null
}

variable "iam_database_users" {
  description = "PostgreSQL database usernames granted IAM authentication access (rds-db:connect) in the generated IAM policy across both primary and secondary clusters. When empty, defaults to [<database_name>, <database_name>_app, <database_name>_readonly]."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_database_users : can(regex("^[a-zA-Z_][a-zA-Z0-9_$-]{0,62}$", u))])
    error_message = "Each entry in iam_database_users must be an explicit PostgreSQL role identifier (wildcards are disallowed)."
  }
}

variable "client_iam_role_names" {
  description = "Optional list of existing EKS service IAM role names (IRSA / EKS Pod Identity) to which the module will attach the rds-db:connect IAM policy."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Data Protection, Backups, Encryption & Compliance
# -----------------------------------------------------------------------------

variable "kms_key_arns" {
  description = "Optional pre-existing regional KMS CMK ARNs for encryption in primary and secondary regions. When omitted, dedicated customer-managed KMS keys with automatic rotation are provisioned in each region."
  type = object({
    primary   = optional(string)
    secondary = optional(string)
  })
  default = {}
}

variable "backup_retention_period" {
  description = "Number of days to retain automated continuous backups (point-in-time recovery). Minimum 7 days enforced for customer/payment data."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period must be an integer between 7 and 35 days."
  }
}

variable "deletion_protection" {
  description = "Protect the global and regional Aurora clusters from accidental deletion."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip creating a final DB cluster snapshot if the primary cluster is destroyed."
  type        = bool
  default     = false
}

variable "preferred_backup_window" {
  description = "Daily UTC time range during which automated backups are created."
  type        = string
  default     = "07:00-08:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC time range during which system maintenance can occur."
  type        = string
  default     = "sun:08:30-sun:09:30"
}

variable "apply_immediately" {
  description = "Whether cluster/instance modifications are applied immediately rather than during the next maintenance window."
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Automatically apply minor PostgreSQL security/patch updates during maintenance windows."
  type        = bool
  default     = true
}

variable "additional_cluster_parameters" {
  description = "Optional service-specific PostgreSQL cluster parameters merged on top of the module's security/audit baseline."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []

  validation {
    condition = alltrue([
      for p in var.additional_cluster_parameters :
      contains(["immediate", "pending-reboot"], p.apply_method) && p.name != "rds.force_ssl"
    ])
    error_message = "apply_method must be 'immediate' or 'pending-reboot', and 'rds.force_ssl' cannot be overridden (TLS is mandatory for customer and payment data)."
  }
}

# -----------------------------------------------------------------------------
# Observability, Audit Logging, Alerting & Optional DNS
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Retention period in days for CloudWatch audit and database log groups in both regions."
  type        = number
  default     = 365

  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention value >= 30 days."
  }
}

variable "monitoring_interval" {
  description = "Granularity in seconds for RDS Enhanced Monitoring OS metrics (0 disables, 1/5/10/15/30/60 enables)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of 0, 1, 5, 10, 15, 30, or 60."
  }
}

variable "performance_insights_retention_period" {
  description = "Retention period in days for Performance Insights data (7 days free tier, or 31-731 days)."
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_period == 7 || (var.performance_insights_retention_period >= 31 && var.performance_insights_retention_period <= 731)
    error_message = "performance_insights_retention_period must be 7 or between 31 and 731."
  }
}

variable "rpo_lag_alarm_threshold_ms" {
  description = "CloudWatch alarm threshold in milliseconds for AuroraGlobalDBReplicationLag between primary and secondary regions (guards the few-seconds RPO objective)."
  type        = number
  default     = 5000

  validation {
    condition     = var.rpo_lag_alarm_threshold_ms >= 1000 && var.rpo_lag_alarm_threshold_ms <= 30000
    error_message = "rpo_lag_alarm_threshold_ms must be between 1000 ms (1s) and 30000 ms (30s)."
  }
}

variable "alarm_sns_topic_arns" {
  description = "Optional regional SNS topic ARNs to receive CloudWatch alarm notifications for replication lag (RPO), CPU, and capacity."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "route53_zone_id" {
  description = "Optional Route 53 Hosted Zone ID in which to create writer and regional reader CNAME records for seamless service endpoint configuration."
  type        = string
  default     = null
}

variable "route53_domain_suffix" {
  description = "Domain suffix matching route53_zone_id (e.g. 'internal.example.com') used when route53_zone_id is set."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags merged onto all provisioned AWS resources."
  type        = map(string)
  default     = {}
}
