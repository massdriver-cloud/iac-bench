variable "name" {
  description = "Service database identifier; unique within these AWS regions."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Use 2-20 lowercase letters, digits or single hyphens; start with a letter and end with a letter or digit."
  }
}

variable "environment" {
  description = "Network environment: staging or prod (VPC Name tag apps-<environment>)."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "Choose a US commercial AWS region."
  }
}

variable "secondary_region" {
  type    = string
  default = "us-west-2"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region)
    error_message = "Choose a US commercial AWS region."
  }
}

variable "clients" {
  description = "Existing EKS workload security groups and IAM role names, by initial regional role. Prefer pod security groups; roles must already exist."
  type = object({
    primary = object({
      security_group_ids = set(string)
      iam_role_names     = set(string)
    })
    secondary = object({
      security_group_ids = set(string)
      iam_role_names     = set(string)
    })
  })
  validation {
    condition = alltrue([
      for client in [var.clients.primary, var.clients.secondary] :
      length(client.security_group_ids) > 0 && length(client.iam_role_names) > 0 &&
      alltrue([for id in client.security_group_ids : can(regex("^sg-[0-9a-f]+$", id))]) &&
      alltrue([for role in client.iam_role_names : can(regex("^[a-zA-Z0-9_+=,.@-]{1,64}$", role))])
    ])
    error_message = "Both regions require at least one workload security group ID and valid IAM role name (not ARN)."
  }
}

variable "database_name" {
  type        = string
  description = "Initial PostgreSQL database."
  default     = "app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "Use a lowercase SQL identifier, at most 63 characters."
  }
}

variable "database_user" {
  type        = string
  description = "Non-owner application login, created by the bootstrap procedure in README.md."
  default     = "app_runtime"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_user)) && !contains(["postgres", "platform_admin", "rdsadmin"], var.database_user)
    error_message = "Use a non-administrative lowercase SQL identifier."
  }
}

variable "engine_version" {
  type        = string
  default     = "16.6"
  description = "Exact Aurora PostgreSQL 16 version supported in BOTH regions. Upgrades are explicitly scheduled and tested."
  validation {
    condition     = can(regex("^16\\.[0-9]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "This module's parameter groups target Aurora PostgreSQL 16."
  }
}

variable "instance_class" {
  type        = string
  default     = "db.r7g.large"
  description = "Identical provisioned capacity in both regions, including warm failover capacity. Confirm regional/version availability."
  validation {
    condition     = can(regex("^db\\.r[678][gi]?\\.(large|xlarge|[0-9]+xlarge)$", var.instance_class))
    error_message = "Use a provisioned memory-optimized Aurora instance class."
  }
}

variable "alarm_email" {
  type        = string
  default     = null
  nullable    = true
  description = "Optional on-call email; confirm both regional subscriptions. Integrate SNS outputs with the production pager before go-live."
  validation {
    condition     = var.alarm_email == null ? true : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alarm_email))
    error_message = "Provide a valid paging email or null when integrating SNS externally."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
