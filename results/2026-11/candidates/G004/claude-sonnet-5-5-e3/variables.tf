variable "name" {
  description = "Service name. Used to name every resource (e.g. \"checkout\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment the database belongs to. Selects the apps-<environment> VPC in each region."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "primary_region" {
  description = "Region hosting the writer cluster."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Region hosting the cross-region replica cluster used for disaster recovery."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "secondary_region must differ from primary_region."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (must support Aurora Global Database). Minor upgrades are applied deliberately, never automatically, so both regions stay on the same version."
  type        = string
  default     = "16.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version must look like \"16.4\"."
  }
}

variable "instance_class" {
  description = "Instance class for all cluster instances. Identical in both regions so the secondary can carry the full load after failover."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Instances in the primary region (one writer plus readers). 2 or more gives in-region failover."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 1
    error_message = "primary_instance_count must be at least 1."
  }
}

variable "secondary_instance_count" {
  description = "Instances in the secondary region. At least 1 is required so the region can be promoted quickly."
  type        = number
  default     = 1

  validation {
    condition     = var.secondary_instance_count >= 1
    error_message = "secondary_instance_count must be at least 1 for disaster recovery."
  }
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master (admin) username. Its password is generated and managed by RDS in Secrets Manager. Services should use IAM authentication instead."
  type        = string
  default     = "dbadmin"
}

variable "client_security_group_ids" {
  description = "Security groups in the primary region (e.g. EKS node/pod security groups) allowed to connect on 5432."
  type        = list(string)
  default     = []
}

variable "secondary_client_security_group_ids" {
  description = "Security groups in the secondary region allowed to connect on 5432."
  type        = list(string)
  default     = []
}

variable "backup_retention_days" {
  description = "Days to retain automated backups in each region."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "deletion_protection" {
  description = "Protect clusters and the global cluster from deletion. Leave enabled for real workloads."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on cluster deletion. Leave false for real workloads."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
