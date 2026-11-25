variable "name" {
  description = "Service/database identifier, unique in the account and regions."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,35}$", var.name)) && !endswith(var.name, "-") && !strcontains(var.name, "--")
    error_message = "name must start with a lowercase letter, contain only lowercase letters, digits and single hyphens, and be at most 36 characters."
  }
}

variable "environment" {
  type        = string
  description = "Network environment: selects the apps-staging or apps-prod VPC."
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region) && var.primary_region != var.secondary_region
    error_message = "Regions must be distinct US commercial AWS regions."
  }
}
variable "secondary_region" {
  type    = string
  default = "us-west-2"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region)
    error_message = "secondary_region must be a US commercial AWS region."
  }
}
variable "database_name" {
  type    = string
  default = "appdb"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain at most 63 letters, digits or underscores."
  }
}
variable "primary_client_security_group_ids" {
  description = "EKS workload security groups allowed to connect in the primary region. Empty denies all inbound connections."
  type        = set(string)
  default     = []
}
variable "secondary_client_security_group_ids" {
  description = "EKS workload security groups allowed to connect in the secondary region. Empty denies all inbound connections."
  type        = set(string)
  default     = []
}
variable "instance_class" {
  description = "Aurora PostgreSQL provisioned instance class, supported in both regions."
  type        = string
  default     = "db.r6g.large"
}
variable "engine_version" {
  description = "Aurora PostgreSQL 16 version supported by global databases in both regions."
  type        = string
  default     = "16.6"
  validation {
    condition     = can(regex("^16\\.[0-9]+", var.engine_version))
    error_message = "This module's parameter groups target Aurora PostgreSQL 16."
  }
}
variable "tags" {
  type    = map(string)
  default = {}
}
