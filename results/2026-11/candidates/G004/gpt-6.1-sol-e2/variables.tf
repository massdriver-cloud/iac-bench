variable "name" {
  description = "Service database identifier; unique in this account and both regions."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Use 3-30 lowercase alphanumeric/hyphen characters, starting with a letter, without consecutive hyphens."
  }
}
variable "environment" {
  description = "Network-owned VPC Name tag in each region."
  type        = string
  default     = "apps-prod"
  validation {
    condition     = contains(["apps-prod", "apps-staging"], var.environment)
    error_message = "Choose apps-prod or apps-staging."
  }
}
variable "primary_region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "Select a US commercial AWS region."
  }
}
variable "secondary_region" {
  type    = string
  default = "us-west-2"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region) && var.secondary_region != var.primary_region
    error_message = "Secondary must be a different US commercial region."
  }
}
variable "client_security_group_ids" {
  description = "Security groups attached to EKS application pods/nodes in each regional VPC. Only these groups can connect on 5432."
  type = object({
    primary   = set(string)
    secondary = set(string)
  })
  validation {
    condition     = length(var.client_security_group_ids.primary) > 0 && length(var.client_security_group_ids.secondary) > 0 && alltrue([for id in setunion(var.client_security_group_ids.primary, var.client_security_group_ids.secondary) : can(regex("^sg-[a-f0-9]+$", id))])
    error_message = "Supply at least one valid application security group ID per region."
  }
}
variable "database_users" {
  description = "PostgreSQL login names mapped to existing EKS IAM role names in each region. Creates narrowly scoped rds-db:connect inline policies; SQL role creation/grants are a bootstrap task (see README)."
  type = map(object({
    primary_role_name   = string
    secondary_role_name = string
  }))
  validation {
    condition     = length(var.database_users) > 0 && alltrue([for name, roles in var.database_users : can(regex("^[a-z][a-z0-9_]{0,62}$", name)) && name != "dbadmin" && length(roles.primary_role_name) > 0 && length(roles.secondary_role_name) > 0])
    error_message = "Supply at least one lowercase SQL username (not dbadmin) and its two existing EKS role names."
  }
}
variable "alarm_email" {
  description = "Monitored on-call email address; confirm the SNS subscription in BOTH regions."
  type        = string
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alarm_email))
    error_message = "Supply an on-call email address."
  }
}
variable "engine_version" {
  description = "Aurora PostgreSQL 16 release available for Global Database in both regions. Upgrade deliberately after testing; major upgrades require coordinated operations."
  type        = string
  default     = "16.9"
  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "This module uses the aurora-postgresql16 parameter family. Select a 16.x release."
  }
}
variable "instance_class" {
  description = "Provisioned Global Database-compatible instance class in both regions; size for full production traffic in either region."
  type        = string
  default     = "db.r7g.large"
  validation {
    condition     = can(regex("^db\\.r(6g|7g|8g)\\.(large|xlarge|[248]xlarge|1[26]xlarge)$", var.instance_class))
    error_message = "Select a provisioned Graviton R-family instance supported in both regions."
  }
}
variable "tags" {
  type        = map(string)
  description = "Additional organization tags."
  default     = {}
}
