###############################################################################
# Required: what is specific to each service
###############################################################################

variable "service" {
  description = "Name of the service that owns this database (for example \"checkout\"). Used to name every resource."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.service)) && length(var.service) <= 24
    error_message = "service must be 1-24 characters of lowercase letters, digits and single hyphens, starting with a letter."
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

###############################################################################
# Placement
###############################################################################

variable "primary_region" {
  description = "Region that hosts the writer in normal operation."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "primary_region must be a US commercial region (us-east-1, us-east-2, us-west-1, us-west-2)."
  }
}

variable "secondary_region" {
  description = "Disaster-recovery region. Holds a continuously replicated, fully sized copy of the database that is promoted if the primary region fails."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region)
    error_message = "secondary_region must be a US commercial region (us-east-1, us-east-2, us-west-1, us-west-2)."
  }

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must differ from primary_region: the point of this module is surviving the loss of a region."
  }
}

###############################################################################
# Sizing
###############################################################################

variable "instance_class" {
  description = "Instance class used for every instance in both regions. The DR region is sized identically so it can take full production load the moment it is promoted."
  type        = string
  default     = "db.r6g.large"

  validation {
    condition     = can(regex("^db\\.(r|x)[0-9][a-z0-9]*\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must be a memory-optimised class (db.r* or db.x*). Burstable (db.t*) classes are not supported by Aurora global databases."
  }
}

variable "instances_per_region" {
  description = "Number of Aurora instances in each region, spread across availability zones. Production requires at least 2 so a single instance or AZ failure is handled inside the region, in seconds, without a cross-region failover."
  type        = number
  default     = 2

  validation {
    condition     = var.instances_per_region >= 1 && var.instances_per_region <= 15 && floor(var.instances_per_region) == var.instances_per_region
    error_message = "instances_per_region must be a whole number between 1 and 15."
  }

  validation {
    condition     = var.environment != "prod" || var.instances_per_region >= 2
    error_message = "prod databases need at least 2 instances per region."
  }
}

###############################################################################
# Engine
###############################################################################

variable "engine_version" {
  description = "Aurora PostgreSQL version (major.minor). Pinned on purpose: a global database is upgraded deliberately by changing this value, never automatically."
  type        = string
  default     = "17.9"

  validation {
    condition     = can(regex("^[0-9]{2}\\.[0-9]{1,2}$", var.engine_version))
    error_message = "engine_version must look like \"17.9\"."
  }
}

variable "database_name" {
  description = "Name of the initial database. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only lowercase letters, digits and underscores (max 63 characters)."
  }
}

variable "master_username" {
  description = "Break-glass administrator user. Services should not use it; they authenticate with IAM (see iam_database_users)."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,15}$", var.master_username)) && !contains(["postgres", "admin", "rdsadmin", "root", "user"], var.master_username)
    error_message = "master_username must be 1-16 lowercase letters, digits or underscores, start with a letter, and not be a reserved or guessable name (postgres, admin, rdsadmin, root, user)."
  }
}

variable "master_password_version" {
  description = "Increase by one to generate a new master password and store it in Secrets Manager. The password itself never appears in state or plan output."
  type        = number
  default     = 1

  validation {
    condition     = var.master_password_version >= 1 && floor(var.master_password_version) == var.master_password_version
    error_message = "master_password_version must be a positive whole number."
  }
}

###############################################################################
# Access
###############################################################################

variable "iam_database_users" {
  description = "PostgreSQL users that services log in as using IAM database authentication (short-lived tokens instead of passwords). Defaults to one user named after the service. The users themselves must be created in the database and granted the rds_iam role."
  type        = list(string)
  default     = null

  validation {
    condition = var.iam_database_users == null ? true : (
      length(var.iam_database_users) > 0 &&
      alltrue([for u in var.iam_database_users : can(regex("^[a-z][a-z0-9_]{0,62}$", u))])
    )
    error_message = "iam_database_users must contain at least one name; each must start with a letter and contain only lowercase letters, digits and underscores."
  }
}

variable "iam_auth_role_names" {
  description = "Names of the IAM roles your service's pods assume (IRSA or EKS Pod Identity). Each is granted permission to connect as the iam_database_users in both regions."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Additional security groups allowed to reach the database on its port, per region. The module always creates a dedicated client security group per region (see outputs) that is allowed in; use this only for clients that cannot carry that group."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "allowed_cidr_blocks" {
  description = "CIDR ranges allowed to reach the database on its port, per region. Prefer security groups; this exists for clients without one (for example an on-premises range routed in by the network team)."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}

  validation {
    condition = alltrue([
      for c in concat(var.allowed_cidr_blocks.primary, var.allowed_cidr_blocks.secondary) :
      try(cidrhost(c, 0) != "" && tonumber(split("/", c)[1]) >= 16, false)
    ])
    error_message = "allowed_cidr_blocks entries must be valid IPv4 CIDRs no wider than /16. Opening the database to the internet (0.0.0.0/0) is never allowed."
  }
}

variable "enable_write_forwarding" {
  description = "Let services in the DR region send writes to their local cluster, which forwards them to the writer in the primary region. Keeps pods in both regions on a local endpoint without needing a cross-region network path."
  type        = bool
  default     = true
}

###############################################################################
# Resilience and data protection
###############################################################################

variable "backup_retention_days" {
  description = "Days of continuous backup (point-in-time recovery) kept in each region. This protects against bad deploys and operator error, which replication faithfully copies to the other region."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the global database and its clusters. To decommission a database, first set this to false and apply, then destroy."
  type        = bool
  default     = true
}

variable "enforced_rpo_seconds" {
  description = "Hard upper bound on data loss in a regional failover. When set, Aurora pauses commits on the writer whenever the DR region falls further behind than this many seconds (minimum 20, an Aurora limit). Off by default because it makes writes in the healthy region depend on the DR region; replication lag is normally under one second and is alarmed on (replication_lag_alarm_seconds) instead."
  type        = number
  default     = null

  validation {
    condition     = var.enforced_rpo_seconds == null ? true : (var.enforced_rpo_seconds >= 20 && var.enforced_rpo_seconds <= 86400)
    error_message = "enforced_rpo_seconds must be between 20 and 86400, or null to disable."
  }
}

###############################################################################
# Observability
###############################################################################

variable "replication_lag_alarm_seconds" {
  description = "Alarm when cross-region replication lag (the writes that would be lost if the primary region failed right now) stays above this many seconds."
  type        = number
  default     = 5

  validation {
    condition     = var.replication_lag_alarm_seconds >= 1 && var.replication_lag_alarm_seconds <= 300
    error_message = "replication_lag_alarm_seconds must be between 1 and 300."
  }
}

variable "alarm_topic_arns" {
  description = "SNS topics notified when an alarm fires or clears, per region (a CloudWatch alarm can only notify a topic in its own region). Until these are set the alarms exist but page nobody."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "log_retention_days" {
  description = "Days to keep PostgreSQL and audit logs in CloudWatch Logs."
  type        = number
  default     = 365

  validation {
    condition     = contains([90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch Logs retention value of at least 90 days (90, 120, 150, 180, 365, 400, 545, 731, ...)."
  }
}

###############################################################################
# Misc
###############################################################################

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
