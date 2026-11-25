###############################################################################
# What every service must fill in
###############################################################################

variable "service" {
  description = "Name of the service that owns this database (e.g. \"checkout\"). Used in every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.service)) && length(var.service) <= 24
    error_message = "service must be 1-24 characters of lowercase letters, digits and single hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment to deploy into. Selects the network team's VPC named apps-<environment> in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "primary_region" {
  description = "US region where the database writer normally runs. Pick the region closest to most of the service's write traffic."
  type        = string

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "primary_region must be one of us-east-1, us-east-2, us-west-1, us-west-2."
  }
}

variable "secondary_region" {
  description = "US region holding the continuously replicated standby cluster that takes over if primary_region fails. Must differ from primary_region."
  type        = string

  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region)
    error_message = "secondary_region must be one of us-east-1, us-east-2, us-west-1, us-west-2."
  }
}

###############################################################################
# Who may connect
###############################################################################

variable "client_security_group_ids" {
  description = <<-EOT
    Security groups allowed to open PostgreSQL connections (TCP 5432) to the
    database, keyed by region. Typically the EKS node or pod security group of
    the service in that region, e.g.
    { "us-east-1" = ["sg-0abc..."], "us-west-2" = ["sg-0def..."] }.
    Nothing can reach the database until at least one group is listed.
  EOT
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for id in flatten(values(var.client_security_group_ids)) : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "client_security_group_ids values must be security group IDs (sg-...)."
  }
}

variable "app_iam_role_names" {
  description = "Names of the IAM roles the service's pods assume (IRSA / Pod Identity). Each gets permission to log in to the database as app_db_username with IAM authentication, in both regions."
  type        = list(string)
  default     = []
}

variable "app_db_username" {
  description = "PostgreSQL user the service logs in as using IAM authentication. The user must be created once in the database: CREATE USER <name>; GRANT rds_iam TO <name>;"
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.app_db_username))
    error_message = "app_db_username must be a valid lowercase PostgreSQL identifier."
  }
}

###############################################################################
# Sizing
###############################################################################

variable "instance_class" {
  description = "Instance class used for every database instance in both regions (kept identical so the standby region can carry full production load). Global databases require memory-optimised classes."
  type        = string
  default     = "db.r8g.large"

  validation {
    condition     = can(regex("^db\\.[rx][0-9]", var.instance_class))
    error_message = "instance_class must be a memory-optimised class (db.r* or db.x*); burstable db.t* classes are not supported by Aurora global databases."
  }
}

variable "instances_per_region" {
  description = "Number of database instances in each region. 2 or more gives automatic failover between availability zones inside a region; the standby region always keeps running instances so it can be promoted within minutes."
  type        = number
  default     = 2

  validation {
    condition     = var.instances_per_region >= 1 && var.instances_per_region <= 15 && floor(var.instances_per_region) == var.instances_per_region
    error_message = "instances_per_region must be a whole number between 1 and 15."
  }
}

###############################################################################
# Things the module decides for you (override only with a reason)
###############################################################################

variable "database_name" {
  description = "Name of the initial database. Defaults to the service name with hyphens replaced by underscores."
  type        = string
  default     = null

  validation {
    condition     = var.database_name == null || can(regex("^[a-z_][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid lowercase PostgreSQL identifier."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL version (major.minor) for the whole global database. Change it here to upgrade both regions. The plan fails if the version is not offered for global databases in either region."
  type        = string
  default     = "17.11"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version)) && try(tonumber(split(".", var.engine_version)[0]) >= 15, false)
    error_message = "engine_version must look like \"17.11\" and be PostgreSQL 15 or newer."
  }
}

variable "master_username" {
  description = "Name of the break-glass administrator account. Its password is generated and stored in Secrets Manager; services should use IAM authentication instead."
  type        = string
  default     = "dbadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.master_username)) && !contains(["admin", "rdsadmin", "postgres", "public", "user"], var.master_username)
    error_message = "master_username must be a lowercase identifier and not a reserved name."
  }
}

variable "managed_rpo_seconds" {
  description = <<-EOT
    Hard upper bound, in seconds, on how far the standby region may fall behind
    (Aurora "managed RPO", rds.global_db_rpo). If replication lag exceeds it,
    Aurora pauses commits on the writer until the standby catches up, so a
    region failure can never lose more than this many seconds of writes.
    20 is the lowest value Aurora accepts; normal lag is well under one second.
    Set to null to stop enforcing the bound (writes then never pause, but data
    loss on regional failover is no longer capped).
  EOT
  type        = number
  default     = 20

  validation {
    condition     = var.managed_rpo_seconds == null || try(var.managed_rpo_seconds >= 20 && floor(var.managed_rpo_seconds) == var.managed_rpo_seconds, false)
    error_message = "managed_rpo_seconds must be a whole number of at least 20, or null."
  }
}

variable "replication_lag_alarm_seconds" {
  description = "Cross-region replication lag, in seconds, above which the replication-lag alarm fires."
  type        = number
  default     = 5

  validation {
    condition     = var.replication_lag_alarm_seconds >= 1
    error_message = "replication_lag_alarm_seconds must be at least 1."
  }
}

variable "alarm_sns_topic_arns" {
  description = "SNS topics notified by the replication-lag alarms, keyed by region (a CloudWatch alarm can only notify topics in its own region), e.g. { \"us-east-1\" = [\"arn:aws:sns:us-east-1:...\"] }."
  type        = map(list(string))
  default     = {}
}

variable "backup_retention_days" {
  description = "Days of continuous backup kept in each region for point-in-time recovery (protection against bad deploys and accidental deletes, which replication copies faithfully)."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "backup_window" {
  description = "Daily UTC window for automated backups."
  type        = string
  default     = "07:00-08:00"
}

variable "maintenance_window" {
  description = "Weekly UTC window for maintenance. Must not overlap backup_window."
  type        = string
  default     = "sun:08:30-sun:09:30"
}

variable "log_retention_days" {
  description = "Days to keep PostgreSQL and audit logs in CloudWatch Logs."
  type        = number
  default     = 365
}

variable "apply_immediately" {
  description = "Apply disruptive changes (instance class, some parameters) immediately instead of in the next maintenance window."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block deletion of the database. Must be set to false (and applied) before the database can be destroyed."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags added to every resource."
  type        = map(string)
  default     = {}
}
