variable "service_name" {
  description = "Short service identifier, used in AWS resource names."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,19}$", var.service_name)) && !endswith(var.service_name, "-") && !strcontains(var.service_name, "--")
    error_message = "Use 1-20 lowercase letters, digits or single hyphens, starting with a letter and not ending with a hyphen."
  }
}
variable "environment" {
  description = "Environment used to find the apps VPC in both regions."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Environment must be staging or prod."
  }
}
variable "primary_region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = startswith(var.primary_region, "us-") && var.primary_region != var.secondary_region
    error_message = "Regions must be distinct US regions."
  }
}
variable "secondary_region" {
  type    = string
  default = "us-west-2"
  validation {
    condition     = startswith(var.secondary_region, "us-")
    error_message = "The secondary must be a US region."
  }
}
variable "primary_client_security_group_ids" {
  description = "EKS client security groups allowed to connect in the primary VPC."
  type        = set(string)
  validation {
    condition     = length(var.primary_client_security_group_ids) > 0 && alltrue([for id in var.primary_client_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "Supply at least one primary-region security group ID."
  }
}
variable "secondary_client_security_group_ids" {
  description = "EKS client security groups allowed to connect in the secondary VPC."
  type        = set(string)
  validation {
    condition     = length(var.secondary_client_security_group_ids) > 0 && alltrue([for id in var.secondary_client_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "Supply at least one secondary-region security group ID."
  }
}
variable "primary_alarm_topic_arn" {
  description = "SNS topic in the primary region for database alarms."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:sns:${var.primary_region}:[0-9]{12}:[A-Za-z0-9_-]+$", var.primary_alarm_topic_arn))
    error_message = "Supply a standard SNS topic ARN in the primary region."
  }
}
variable "secondary_alarm_topic_arn" {
  description = "SNS topic in the secondary region for replication alarms."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:sns:${var.secondary_region}:[0-9]{12}:[A-Za-z0-9_-]+$", var.secondary_alarm_topic_arn))
    error_message = "Supply a standard SNS topic ARN in the secondary region."
  }
}
variable "engine_version" {
  description = "Aurora PostgreSQL 16 version supported by global databases in both regions. Upgrade deliberately after checking regional availability."
  type        = string
  default     = "16.6"
  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "Use an Aurora PostgreSQL 16 minor version, for example 16.6."
  }
}
variable "instance_class" {
  description = "Provisioned Aurora instance class available in both regions."
  type        = string
  default     = "db.r6g.large"
}
variable "master_username" {
  type    = string
  default = "dbadmin"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "Master username must start with a letter and contain only letters, digits and underscores."
  }
}
variable "database_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "Database name must start with a letter and contain only letters, digits and underscores."
  }
}
