variable "name" {
  description = "Unique service database name, also used as the global cluster identifier."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Use 2-40 lowercase letters, digits or single hyphens, beginning with a letter and ending with a letter or digit."
  }
}
variable "environment" {
  type        = string
  default     = "prod"
  description = "Selects the network team's VPC tagged Name=apps-<environment>."
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Choose staging or prod."
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
    error_message = "Select a different US commercial AWS region."
  }
}
variable "database_name" {
  type    = string
  default = "app"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "Use a PostgreSQL identifier of at most 63 characters."
  }
}
variable "engine_version" {
  description = "Pin an Aurora PostgreSQL 16 minor release available in both regions. Upgrades are deliberate and must be tested globally."
  type        = string
  default     = "16.6"
  validation {
    condition     = startswith(var.engine_version, "16.")
    error_message = "This module's parameter groups target PostgreSQL 16."
  }
}
variable "instance_class" {
  type        = string
  default     = "db.r7g.large"
  description = "Provisioned instance size, identical in both regions so the DR site can carry production traffic."
  validation {
    condition     = can(regex("^db\\.(r6g|r7g|r8g)\\.", var.instance_class))
    error_message = "Use a provisioned memory-optimized Graviton Aurora instance class."
  }
}
variable "primary_client_security_group_ids" {
  description = "Local EKS node or pod security groups permitted to connect in the primary VPC."
  type        = set(string)
  validation {
    condition     = length(var.primary_client_security_group_ids) > 0 && alltrue([for id in var.primary_client_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "Supply at least one local client security group."
  }
}
variable "secondary_client_security_group_ids" {
  description = "Local EKS node or pod security groups permitted to connect in the secondary VPC."
  type        = set(string)
  validation {
    condition     = length(var.secondary_client_security_group_ids) > 0 && alltrue([for id in var.secondary_client_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "Supply at least one local client security group."
  }
}
variable "application_role_names" {
  description = "Existing EKS IRSA or Pod Identity IAM roles to grant rds-db:connect. These roles must already have correct workload trust policies."
  type        = set(string)
  validation {
    condition     = length(var.application_role_names) > 0
    error_message = "Supply at least one existing application role."
  }
}
variable "application_database_user" {
  description = "Non-admin PostgreSQL login to bootstrap with rds_iam and least-privilege SQL grants."
  type        = string
  default     = "app_iam"
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.application_database_user)) && !contains(["postgres", "dbadmin", "rdsadmin"], var.application_database_user)
    error_message = "Supply a non-administrative PostgreSQL username."
  }
}
variable "alarm_email" {
  description = "On-call mailbox; confirm the SNS subscription in BOTH regions. Integrate with your paging service for production."
  type        = string
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alarm_email))
    error_message = "Supply a valid on-call email address."
  }
}
variable "tags" {
  type    = map(string)
  default = {}
}
locals {
  tags = merge(var.tags, { Service = var.name, Environment = var.environment, ManagedBy = "OpenTofu", DataClassification = "confidential" })
}
