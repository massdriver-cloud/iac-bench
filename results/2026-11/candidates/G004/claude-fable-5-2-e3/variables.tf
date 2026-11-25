# ---------------------------------------------------------------------------
# What every service must fill in
# ---------------------------------------------------------------------------

variable "service" {
  description = "Name of the service that owns this database (e.g. \"checkout\"). Used in every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.service)) && !strcontains(var.service, "--")
    error_message = "service must be 3-24 characters of lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment to deploy into. Selects the network team's VPC (apps-<environment>) in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "primary_region" {
  description = "US region that hosts the writer on day one (e.g. \"us-east-1\")."
  type        = string

  validation {
    condition     = can(regex("^us-(east|west)-[0-9]$", var.primary_region))
    error_message = "primary_region must be a commercial US region (us-east-1, us-east-2, us-west-1 or us-west-2): customer and payment data stays in the US."
  }
}

variable "secondary_region" {
  description = "US region that hosts the warm standby the database fails over to (e.g. \"us-west-2\"). Must differ from primary_region."
  type        = string

  validation {
    condition     = can(regex("^us-(east|west)-[0-9]$", var.secondary_region))
    error_message = "secondary_region must be a commercial US region (us-east-1, us-east-2, us-west-1 or us-west-2): customer and payment data stays in the US."
  }

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must be a different region from primary_region, otherwise a regional outage takes out both copies."
  }
}

# ---------------------------------------------------------------------------
# Who may connect
# ---------------------------------------------------------------------------

variable "client_security_group_ids" {
  description = "Security groups (EKS pod or node groups) allowed to reach PostgreSQL on 5432, per region. Nothing else can connect; with the default nothing can."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "app_database_users" {
  description = "PostgreSQL users that services log in as using IAM authentication (no passwords). The module creates an IAM policy allowing rds-db:connect as these users; the users themselves must be created in the database and granted the rds_iam role."
  type        = list(string)
  default     = ["app"]
  nullable    = false

  validation {
    condition     = alltrue([for u in var.app_database_users : can(regex("^[a-z_][a-z0-9_]{0,62}$", u))])
    error_message = "Each database user must be a valid lowercase PostgreSQL identifier."
  }
}

variable "app_role_names" {
  description = "Names of the IAM roles the service's pods run as (IRSA / Pod Identity). Each gets the database-connect policy attached."
  type        = list(string)
  default     = []
  nullable    = false
}

# ---------------------------------------------------------------------------
# Sizing and engine
# ---------------------------------------------------------------------------

variable "database_name" {
  description = "Name of the initial database. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only lowercase letters, digits and underscores."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version, applied to the whole global database. Change it here to upgrade both regions together."
  type        = string
  default     = "16.8"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must be of the form <major>.<minor>, e.g. \"16.8\"."
  }
}

variable "instance_class" {
  description = "Instance class used for every instance in both regions. The standby is sized identically so it can take full production load the moment it is promoted."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.[rx][0-9]", var.instance_class))
    error_message = "instance_class must be a memory-optimised class (db.r* or db.x*). Burstable db.t* classes are not supported by Aurora Global Database."
  }
}

variable "instances_per_region" {
  description = "Number of instances in each region (one writer or replica-writer plus readers), spread across Availability Zones. At least 2 so that losing a single AZ never requires a cross-region failover."
  type        = number
  default     = 2

  validation {
    condition     = var.instances_per_region >= 2 && var.instances_per_region <= 15 && floor(var.instances_per_region) == var.instances_per_region
    error_message = "instances_per_region must be a whole number between 2 and 15."
  }
}

# ---------------------------------------------------------------------------
# Recovery and protection
# ---------------------------------------------------------------------------

variable "backup_retention_days" {
  description = "Days of continuous backup (point-in-time recovery) kept in each region."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "replication_lag_alarm_seconds" {
  description = "Cross-region replication lag, in seconds, above which the replication-lag alarm fires. Lag is the amount of committed writes that would be lost if the writer region failed right now."
  type        = number
  default     = 5

  validation {
    condition     = var.replication_lag_alarm_seconds >= 1
    error_message = "replication_lag_alarm_seconds must be at least 1."
  }
}

variable "alarm_topic_arns" {
  description = "SNS topics notified when cross-region replication lag breaches the threshold, per region (CloudWatch can only notify topics in the alarm's own region)."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "enforced_rpo_seconds" {
  description = "Opt-in hard cap on data loss (Aurora managed RPO, rds.global_db_rpo). When set, the writer PAUSES COMMITS whenever the other region is more than this many seconds behind, so a problem in the standby region stops writes in the healthy one. Minimum 20. Leave null to favour availability."
  type        = number
  default     = null

  validation {
    condition     = var.enforced_rpo_seconds == null ? true : var.enforced_rpo_seconds >= 20 && floor(var.enforced_rpo_seconds) == var.enforced_rpo_seconds
    error_message = "enforced_rpo_seconds must be a whole number of at least 20 (the smallest value Aurora accepts), or null."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the database. Set to false (and apply) only as the deliberate first step of decommissioning."
  type        = bool
  default     = true
  nullable    = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot taken when a cluster is destroyed. Leave false for anything holding real data."
  type        = bool
  default     = false
  nullable    = false
}

variable "master_password_version" {
  description = "Increment to rotate the break-glass master password. A new password is generated, stored in Secrets Manager and set on the database in the same apply."
  type        = number
  default     = 1
  nullable    = false
}

variable "log_retention_days" {
  description = "Days to keep PostgreSQL logs (connections, disconnections, DDL) in CloudWatch Logs. The default keeps a little over a year of audit trail."
  type        = number
  default     = 400

  validation {
    condition     = contains([90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value of at least 90 days (90, 120, 150, 180, 365, 400, 545, 731, ...)."
  }
}

variable "tags" {
  description = "Extra tags applied to every resource in both regions."
  type        = map(string)
  default     = {}
  nullable    = false
}
