variable "name" {
  description = "Service slug; the environment suffix is added to AWS names."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) <= 36
    error_message = "name must be a lowercase service slug of at most 36 characters."
  }
}

variable "environment" {
  description = "Environment suffix used to find the apps-<environment> VPCs."
  type        = string
  default     = "prod"
  nullable    = false
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "regions" {
  description = "Initial primary and recovery region. Do not swap these after a failover."
  type        = object({ primary = string, secondary = string })
  nullable    = false
  validation {
    condition     = var.regions.primary != var.regions.secondary && alltrue([for r in [var.regions.primary, var.regions.secondary] : can(regex("^us-(east|west)-[0-9]+$", r))])
    error_message = "Specify two distinct commercial US AWS regions that support Aurora Global Database."
  }
}

variable "eks_client_security_groups" {
  description = "Security groups actually associated with the local EKS client ENIs in each apps VPC. Prefer dedicated workload/pod security groups."
  type        = object({ primary = set(string), secondary = set(string) })
  nullable    = false
  validation {
    condition = alltrue([
      for ids in [var.eks_client_security_groups.primary, var.eks_client_security_groups.secondary] :
      length(ids) > 0 && alltrue([for id in ids : can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", id))])
    ])
    error_message = "Specify at least one valid client security group ID in each region."
  }
}

variable "application_iam_role_names" {
  description = "Existing in-account IAM roles assumed by this service in EKS across both regions (IRSA or Pod Identity); supply one if shared."
  type        = set(string)
  nullable    = false
  validation {
    condition     = length(var.application_iam_role_names) > 0 && alltrue([for name in var.application_iam_role_names : can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", name))])
    error_message = "Supply one or more IAM role names, not paths or ARNs."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name. Treat as immutable after creation."
  type        = string
  default     = "app"
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name)) && !contains(["postgres", "template0", "template1", "rdsadmin"], var.database_name)
    error_message = "Specify a non-reserved, lowercase PostgreSQL identifier up to 63 characters."
  }
}

variable "application_db_user" {
  description = "Non-admin PostgreSQL login for the service; create it during SQL bootstrap."
  type        = string
  default     = "app_runtime"
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.application_db_user)) && !can(regex("^(pg_|rds|platform_admin$|postgres$)", var.application_db_user))
    error_message = "Specify a non-reserved lowercase PostgreSQL login distinct from the admin."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL 16 minor version supported for global databases in both selected regions. Change in a coordinated maintenance window."
  type        = string
  default     = "16.11"
  nullable    = false
  validation {
    condition     = can(regex("^16\\.[0-9]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "Specify an Aurora PostgreSQL 16 minor version, e.g. 16.11."
  }
}

variable "instance_class" {
  description = "Provisioned Aurora instance class, sized for peak production traffic in either region. Each region gets two instances."
  type        = string
  default     = "db.r7g.large"
  nullable    = false
}

variable "incident_topic_arns" {
  description = "Optional existing regional SNS incident topics. If omitted, the module creates a topic to subscribe in each region."
  type        = object({ primary = optional(string), secondary = optional(string) })
  default     = {}
  nullable    = false
}

variable "tags" {
  description = "Additional AWS tags. Standard service and environment tags take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
