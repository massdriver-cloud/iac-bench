variable "name" {
  description = "Unique service database identifier, also used for AWS resource names."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Use 3-31 lowercase letters, numbers or hyphens, starting with a letter, with no trailing or doubled hyphens."
  }
}

variable "environment" {
  description = "Network environment; selects the VPC tagged Name=apps-<environment> in each region."
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "Environment must be prod or staging."
  }
}

variable "database_name" {
  description = "Initial application database. This is not a PostgreSQL login name."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "Use a lowercase PostgreSQL identifier of up to 63 characters."
  }
}

variable "application_db_user" {
  description = "Non-admin PostgreSQL login to bootstrap with rds_iam; IAM roles below may connect only as this user."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.application_db_user)) && !contains(["postgres", "dbadmin", "rdsadmin"], var.application_db_user)
    error_message = "Use a lowercase non-admin PostgreSQL identifier."
  }
}

variable "application_iam_role_names" {
  description = "Existing same-account EKS workload IAM role names (IRSA or Pod Identity), in either region. Not node roles or role ARNs."
  type        = set(string)
  validation {
    condition     = length(var.application_iam_role_names) > 0 && alltrue([for role in var.application_iam_role_names : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", role))])
    error_message = "Supply at least one existing IAM role name."
  }
}

variable "primary_client_security_group_ids" {
  description = "EKS pod/node security groups allowed to connect in the primary VPC. No CIDR ingress is opened."
  type        = set(string)
  validation {
    condition     = length(var.primary_client_security_group_ids) > 0 && alltrue([for id in var.primary_client_security_group_ids : can(regex("^sg-[a-f0-9]+$", id))])
    error_message = "Supply at least one security group ID in the primary VPC."
  }
}

variable "secondary_client_security_group_ids" {
  description = "EKS pod/node security groups allowed to connect in the secondary VPC."
  type        = set(string)
  validation {
    condition     = length(var.secondary_client_security_group_ids) > 0 && alltrue([for id in var.secondary_client_security_group_ids : can(regex("^sg-[a-f0-9]+$", id))])
    error_message = "Supply at least one security group ID in the secondary VPC."
  }
}

variable "primary_region" {
  description = "Initial writer region; do not swap these inputs to perform failover."
  type        = string
  default     = "us-east-1"
  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.primary_region))
    error_message = "Choose a commercial US AWS region."
  }
}

variable "secondary_region" {
  description = "Warm global secondary and disaster-recovery control-plane region."
  type        = string
  default     = "us-west-2"
  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.secondary_region)) && var.secondary_region != var.primary_region
    error_message = "Choose a distinct commercial US AWS region."
  }
}

variable "engine_version" {
  description = "Approved Aurora PostgreSQL 16 minor version, available for Global Database in both regions. Changes require a tested maintenance rollout."
  type        = string
  default     = "16.9"
  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "This module pins its parameter family to Aurora PostgreSQL 16."
  }
}

variable "instance_class" {
  description = "Provisioned, Global Database-compatible Graviton instance class; equal capacity in both regions. Size using load tests."
  type        = string
  default     = "db.r7g.large"
  validation {
    condition     = can(regex("^db\\.r[678]g\\.(large|xlarge|[248]xlarge|16xlarge)$", var.instance_class))
    error_message = "Use a provisioned Graviton memory-optimized class supported in both regions."
  }
}

variable "instances_per_region" {
  description = "At least two warm instances per region, explicitly distributed across AZs."
  type        = number
  default     = 2
  validation {
    condition     = var.instances_per_region >= 2 && var.instances_per_region <= 8 && floor(var.instances_per_region) == var.instances_per_region
    error_message = "Use an integer from 2 to 8."
  }
}

variable "alert_email" {
  description = "Monitored on-call mailbox. Confirm both regional SNS subscriptions immediately after apply and integrate with paging."
  type        = string
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alert_email))
    error_message = "Supply an on-call email address."
  }
}

variable "tags" {
  description = "Additional organizational tags. Standard identity and classification tags take precedence."
  type        = map(string)
  default     = {}
}
