variable "name" {
  description = "Service/database identifier, used in resource names."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Use 3-32 lowercase letters, digits or hyphens, beginning with a letter and ending with a letter or digit; no double hyphens."
  }
}
variable "environment" {
  description = "Existing network environment; use the apps-prod or apps-staging VPCs respectively."
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "Environment must be prod or staging."
  }
}
variable "primary_region" {
  type        = string
  description = "Initial writer's US AWS region. Changing this is not a failover operation."
  default     = "us-east-1"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "Choose a commercial US AWS region supporting the selected Aurora version and instance class."
  }
}
variable "secondary_region" {
  type        = string
  description = "Warm recovery region, distinct from primary_region. Changing this is not a failover operation."
  default     = "us-west-2"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region) && var.secondary_region != var.primary_region
    error_message = "Choose a different commercial US AWS region."
  }
}
variable "primary_network" {
  description = "Network team's apps-<environment> VPC, AZ=>private tier=database subnet ID map, and EKS security groups actually attached to client ENIs. No network is created."
  type = object({
    vpc_id                    = string
    database_subnets          = map(string)
    client_security_group_ids = set(string)
  })
  validation {
    condition = (
      can(regex("^vpc-[0-9a-f]+$", var.primary_network.vpc_id)) &&
      length(var.primary_network.database_subnets) >= 2 &&
      length(distinct(values(var.primary_network.database_subnets))) == length(var.primary_network.database_subnets) &&
      alltrue([for az, id in var.primary_network.database_subnets : startswith(az, var.primary_region) && can(regex("^[a-z]{2}-[a-z]+-[0-9][a-z]$", az)) && can(regex("^subnet-[0-9a-f]+$", id))]) &&
      length(var.primary_network.client_security_group_ids) > 0 &&
      alltrue([for id in var.primary_network.client_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    )
    error_message = "Supply a VPC ID, different database subnets in at least two AZs in primary_region, and at least one EKS client SG."
  }
}
variable "secondary_network" {
  description = "Recovery apps-<environment> VPC, AZ=>private tier=database subnet map, and region-local EKS client security groups."
  type = object({
    vpc_id                    = string
    database_subnets          = map(string)
    client_security_group_ids = set(string)
  })
  validation {
    condition = (
      can(regex("^vpc-[0-9a-f]+$", var.secondary_network.vpc_id)) &&
      length(var.secondary_network.database_subnets) >= 2 &&
      length(distinct(values(var.secondary_network.database_subnets))) == length(var.secondary_network.database_subnets) &&
      alltrue([for az, id in var.secondary_network.database_subnets : startswith(az, var.secondary_region) && can(regex("^[a-z]{2}-[a-z]+-[0-9][a-z]$", az)) && can(regex("^subnet-[0-9a-f]+$", id))]) &&
      length(var.secondary_network.client_security_group_ids) > 0 &&
      alltrue([for id in var.secondary_network.client_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    )
    error_message = "Supply a VPC ID, different database subnets in at least two AZs in secondary_region, and at least one EKS client SG."
  }
}
variable "database_name" {
  description = "Initial application database. Roles and schemas are provisioned separately by a database migration/admin job."
  type        = string
  default     = "app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "Use a PostgreSQL identifier of up to 63 lowercase letters, digits or underscores, starting with a letter."
  }
}
variable "engine_version" {
  description = "Pin an Aurora PostgreSQL 16 minor supported for Global Database in BOTH regions. Upgrade deliberately; both regions must match."
  type        = string
  default     = "16.6"
  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "This module uses the aurora-postgresql16 parameter family; supply an exact 16.x version. Major upgrades need a separately tested parameter-family migration."
  }
}
variable "instance_class" {
  description = "Provisioned, Global Database-compatible class available in both regions. Two equal-sized instances per region are always deployed. Size with production load tests."
  type        = string
  default     = "db.r7g.large"
  validation {
    condition     = can(regex("^db\\.[rx][0-9][a-z]*\\.[a-z0-9]+$", var.instance_class))
    error_message = "Choose a provisioned memory-optimized RDS instance class, not a burstable or Serverless class."
  }
}
variable "application_db_user" {
  description = "Non-superuser SQL login used by EKS IAM auth; provision separately, granting rds_iam and least-privilege SQL permissions."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.application_db_user)) && !contains(["postgres", "dbadmin", "rdsadmin"], var.application_db_user)
    error_message = "Choose a non-admin SQL username (lowercase identifier, max 63 characters)."
  }
}
variable "alarm_email" {
  description = "Monitored on-call email; confirm SNS subscriptions in each region after apply. Alarms do not perform unsafe automatic promotion."
  type        = string
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alarm_email))
    error_message = "Supply an on-call email address."
  }
}
variable "tags" {
  type        = map(string)
  description = "Additional tags; reserved Service, Environment and ManagedBy tags are set by the module."
  default     = {}
}
