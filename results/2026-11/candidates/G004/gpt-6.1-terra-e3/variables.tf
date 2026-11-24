variable "service_name" {
  description = "Short, unique service identifier used in AWS resource names."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.service_name)) && !strcontains(var.service_name, "--")
    error_message = "Use 2-24 lowercase letters, digits or single hyphens, beginning with a letter and ending with an alphanumeric character."
  }
}
variable "environment" {
  type        = string
  description = "Network environment (selects the apps-staging or apps-prod VPC)."
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}
variable "primary_region" {
  type        = string
  description = "AWS US region initially hosting the writer."
  validation {
    condition     = can(regex("^us-(east|west)-[0-9]+$", var.primary_region))
    error_message = "Use a US commercial AWS region."
  }
}
variable "secondary_region" {
  type        = string
  description = "Distinct AWS US region hosting the warm disaster recovery cluster."
  validation {
    condition     = can(regex("^us-(east|west)-[0-9]+$", var.secondary_region))
    error_message = "Use a US commercial AWS region."
  }
}
variable "primary_client_security_group_ids" {
  description = "Security groups attached to the application clients in the primary VPC."
  type        = set(string)
  validation {
    condition     = length(var.primary_client_security_group_ids) > 0 && alltrue([for id in var.primary_client_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "Provide at least one application security group ID."
  }
}
variable "secondary_client_security_group_ids" {
  description = "Security groups attached to the application clients in the secondary VPC."
  type        = set(string)
  validation {
    condition     = length(var.secondary_client_security_group_ids) > 0 && alltrue([for id in var.secondary_client_security_group_ids : can(regex("^sg-[0-9a-f]+$", id))])
    error_message = "Provide at least one application security group ID."
  }
}
variable "database_name" {
  description = "Initial application database name."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "Use a PostgreSQL identifier starting with a letter, at most 63 characters."
  }
}
variable "master_username" {
  description = "Administrator username. Applications should use their own least-privilege IAM-authenticated database roles."
  type        = string
  default     = "dbadmin"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username))
    error_message = "Use an administrator name starting with a letter, at most 63 characters."
  }
}
variable "instance_class" {
  description = "Provisioned Aurora instance class, available in both regions."
  type        = string
  default     = "db.r6g.large"
}
variable "engine_version" {
  description = "Aurora PostgreSQL 16 version supported by global databases in both regions. Change deliberately during an upgrade."
  type        = string
  default     = "16.6"
  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "This module's parameter groups target Aurora PostgreSQL 16; use a 16.x version."
  }
}
variable "secondary_alarm_topic_arns" {
  description = "SNS topic ARNs in the secondary region for actionable replication-lag alarms."
  type        = set(string)
  validation {
    condition     = length(var.secondary_alarm_topic_arns) > 0 && alltrue([for arn in var.secondary_alarm_topic_arns : can(regex("^arn:aws:sns:us-(east|west)-[0-9]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn))])
    error_message = "Provide at least one commercial US SNS topic ARN for replication lag alerts."
  }
}
variable "tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
}
