variable "name" {
  description = "Unique service slug within this environment; also used to derive PostgreSQL names."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 25
    error_message = "Use at most 25 lowercase letters, digits, and single hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Selects the existing apps-prod or apps-staging VPC in each region."
  type        = string
  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "environment must be prod or staging."
  }
}

variable "primary_region" {
  description = "Initial writer region. This is not a failover switch."
  type        = string
  default     = "us-east-1"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.primary_region)
    error_message = "Select a commercial US AWS region."
  }
}

variable "secondary_region" {
  description = "Initial hot standby region. This is not a failover switch."
  type        = string
  default     = "us-west-2"
  validation {
    condition     = contains(["us-east-1", "us-east-2", "us-west-1", "us-west-2"], var.secondary_region) && var.secondary_region != var.primary_region
    error_message = "Select a different commercial US AWS region from the primary."
  }
}

variable "eks_source_security_group_ids" {
  description = "Regional source SG IDs carried by the EKS clients (node or pod security groups as appropriate)."
  type = object({
    primary   = set(string)
    secondary = set(string)
  })
  validation {
    condition = (
      length(var.eks_source_security_group_ids.primary) > 0 && length(var.eks_source_security_group_ids.secondary) > 0 &&
      alltrue([for id in setunion(var.eks_source_security_group_ids.primary, var.eks_source_security_group_ids.secondary) : can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", id))])
    )
    error_message = "Supply at least one valid EKS source security group ID per region."
  }
}

variable "additional_client_ipv4_cidrs" {
  description = "Optional private EKS source ranges as seen by each database, e.g. for routed cross-region clients. The module does not establish routing."
  type = object({
    primary   = optional(set(string), [])
    secondary = optional(set(string), [])
  })
  default = {}
  validation {
    condition = alltrue([for cidr in setunion(var.additional_client_ipv4_cidrs.primary, var.additional_client_ipv4_cidrs.secondary) : try(
      can(cidrnetmask(cidr)) && anytrue([
        for private_range in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
        cidrcontains(private_range, cidrhost(cidr, 0)) && cidrcontains(private_range, cidrhost(cidr, -1))
      ]), false)
    ])
    error_message = "Additional source CIDRs must be wholly within RFC 1918 private space."
  }
}

variable "eks_iam_role_names" {
  description = "Existing same-account EKS workload IAM role names to attach the rds-db:connect policy to. Leave empty to attach the exported policy separately."
  type        = set(string)
  default     = []
}

variable "engine_version" {
  description = "Aurora PostgreSQL 16 minor version supported by Global Database in both selected regions. Coordinate changes across both members."
  type        = string
  default     = "16.10"
  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "Provide an exact Aurora PostgreSQL 16 major.minor version."
  }
}

variable "instance_class" {
  description = "Provisioned class used in both regions; size the standby for production writer traffic, not idle traffic."
  type        = string
  default     = "db.r7g.large"
  validation {
    condition     = can(regex("^db\\.(r|x)[0-9][a-z0-9]*\\.[a-z0-9]+$", var.instance_class))
    error_message = "Use a supported provisioned memory-optimized Aurora instance class."
  }
}

variable "alarm_topic_arns" {
  description = "Existing regional SNS topics that route to the database on-call."
  type = object({
    primary   = string
    secondary = string
  })
  validation {
    condition = (
      can(regex("^arn:aws:sns:${var.primary_region}:[0-9]{12}:[A-Za-z0-9_-]+$", var.alarm_topic_arns.primary)) &&
      can(regex("^arn:aws:sns:${var.secondary_region}:[0-9]{12}:[A-Za-z0-9_-]+$", var.alarm_topic_arns.secondary))
    )
    error_message = "Supply a standard SNS topic ARN in each respective region."
  }
}
