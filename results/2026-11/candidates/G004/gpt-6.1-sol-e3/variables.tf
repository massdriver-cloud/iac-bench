variable "name" {
  description = "Service/database identifier; unique within the account and environment."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}[a-z0-9]$", var.name))
    error_message = "Use 3-31 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Selects the network team's VPC named apps-prod or apps-staging."
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "Environment must be prod or staging."
  }
}

variable "primary_region" {
  type        = string
  description = "Initial writer region. Do not swap regions in configuration to perform failover."
  default     = "us-east-1"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "Choose a commercial US region supporting Aurora Global Database."
  }
}

variable "secondary_region" {
  type        = string
  description = "Hot disaster-recovery region, distinct from the primary."
  default     = "us-west-2"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region)
    error_message = "Choose a commercial US region supporting Aurora Global Database."
  }
}

variable "eks_security_group_ids" {
  description = "Security groups actually used by EKS pods/nodes connecting to PostgreSQL, in the corresponding VPCs. No CIDR-based access is allowed."
  type = object({
    primary   = set(string)
    secondary = set(string)
  })
  validation {
    condition = alltrue([
      length(var.eks_security_group_ids.primary) > 0,
      length(var.eks_security_group_ids.secondary) > 0,
      alltrue([for id in concat(tolist(var.eks_security_group_ids.primary), tolist(var.eks_security_group_ids.secondary)) : can(regex("^sg-[0-9a-f]+$", id))])
    ])
    error_message = "Supply at least one EKS security group ID in each region."
  }
}

variable "application_role_names" {
  description = "Existing EKS IRSA/Pod Identity IAM role names, not ARNs. Each receives connect access in BOTH regions so promotion does not require an IAM change. Trust policies remain owned by the EKS team."
  type        = set(string)
  validation {
    condition     = length(var.application_role_names) > 0 && alltrue([for role in var.application_role_names : can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", role))])
    error_message = "Supply at least one valid existing IAM role name."
  }
}

variable "database_users" {
  description = "Non-admin PostgreSQL login names allowed through IAM. SQL roles, rds_iam grants and least-privilege SQL permissions must be bootstrapped separately."
  type        = set(string)
  default     = ["app"]
  validation {
    condition     = length(var.database_users) > 0 && alltrue([for user in var.database_users : can(regex("^[a-z][a-z0-9_]{0,62}$", user)) && !startswith(user, "pg_") && !startswith(user, "rds") && user != "cluster_admin"])
    error_message = "Use non-reserved lowercase PostgreSQL usernames, not cluster_admin."
  }
}

variable "database_name" {
  type        = string
  description = "Initial database, created only at first provisioning."
  default     = "app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "Use a lowercase SQL identifier up to 63 characters."
  }
}

variable "engine_version" {
  type        = string
  description = "Pin an Aurora PostgreSQL 16 minor supported by Global Database in both regions; upgrades must be coordinated."
  default     = "16.6"
  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "This module's parameter groups require PostgreSQL 16."
  }
}

variable "instance_class" {
  type        = string
  description = "Provisioned Graviton class supporting Aurora Global Database in both regions."
  default     = "db.r7g.large"
  validation {
    condition     = can(regex("^db\\.(r6g|r7g|r8g)\\.", var.instance_class))
    error_message = "Choose a production memory-optimized Graviton instance class."
  }
}

variable "instances_per_region" {
  type        = number
  description = "At least two instances per region for local HA, distributed across AZs. Both regions are sized equally to sustain failover traffic."
  default     = 2
  validation {
    condition     = var.instances_per_region >= 2 && var.instances_per_region <= 15 && floor(var.instances_per_region) == var.instances_per_region
    error_message = "Choose an integer from 2 to 15."
  }
}

variable "alarm_email" {
  type        = string
  description = "Monitored operations mailbox. Confirm BOTH regional SNS subscriptions after apply and connect to your paging workflow."
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alarm_email))
    error_message = "Supply an operations email address."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional organizational tags. Standard module tags take precedence."
  default     = {}
}
