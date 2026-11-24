variable "service_name" {
  description = "Short DNS-safe service identifier, unique per environment in this AWS account."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.service_name)) && length(var.service_name) <= 32
    error_message = "Use up to 32 lowercase alphanumerics with optional single hyphens; start with a letter."
  }
}

variable "environment" {
  description = "Network environment; selects the apps-prod or apps-staging VPC in both regions."
  type        = string
  default     = "prod"
  nullable    = false
  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "environment must be prod or staging."
  }
}

variable "primary_region" {
  description = "Initial writer region; not a failover switch."
  type        = string
  default     = "us-east-1"
  nullable    = false
  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.primary_region))
    error_message = "Choose a commercial US AWS region."
  }
}

variable "secondary_region" {
  description = "Initial recovery region; not a failover switch."
  type        = string
  default     = "us-west-2"
  nullable    = false
  validation {
    condition     = can(regex("^us-(east|west)-[12]$", var.secondary_region))
    error_message = "Choose a commercial US AWS region different from the primary."
  }
}

variable "engine_version" {
  description = "Exact Aurora PostgreSQL 16 minor version supported for Global Database and the instance class in both regions."
  type        = string
  default     = "16.9"
  nullable    = false
  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "Specify an exact Aurora PostgreSQL 16 minor version (16.x)."
  }
}

variable "instance_class" {
  description = "Instance class for all four instances. Size for the full writer workload in either region."
  type        = string
  default     = "db.r7g.large"
  nullable    = false
}

variable "primary_client_security_group_id" {
  description = "Existing security group on the EKS pods or nodes that connect to the database in the primary VPC."
  type        = string
  nullable    = false
}

variable "secondary_client_security_group_id" {
  description = "Existing security group on the EKS pods or nodes that connect to the database in the recovery VPC."
  type        = string
  nullable    = false
}

variable "app_iam_role_names" {
  description = "Names (not ARNs) of existing service workload IAM roles to attach the runtime policy to. Leave empty if managed by the EKS stack using the output policy ARN."
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for name in var.app_iam_role_names : can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", name))])
    error_message = "Supply existing IAM role names, without ARNs or paths."
  }
}

variable "alarm_email" {
  description = "On-call email address; confirm both regional SNS subscriptions after apply."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", var.alarm_email))
    error_message = "Enter a valid SNS email subscription address."
  }
}

variable "admin_credential_version" {
  description = "Monotonic generation of the bootstrap/break-glass password. Increment only in a planned rotation with the initial primary region serving writes."
  type        = number
  default     = 1
  nullable    = false
  validation {
    condition     = var.admin_credential_version >= 1 && floor(var.admin_credential_version) == var.admin_credential_version
    error_message = "The credential version must be a positive integer."
  }
}
