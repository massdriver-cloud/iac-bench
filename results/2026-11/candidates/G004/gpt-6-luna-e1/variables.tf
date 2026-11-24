variable "name" {
  description = "Short service/database slug, used as the basis for regional AWS resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,24}[a-z0-9]$", var.name))
    error_message = "name must be 2-26 lowercase letters, digits, or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "environment" {
  description = "Environment whose network is used by this database."
  type        = string

  validation {
    condition     = contains(["apps-staging", "apps-prod"], var.environment)
    error_message = "environment must be apps-staging or apps-prod."
  }
}

variable "primary_region" {
  description = "AWS region hosting the initial writer."
  type        = string
}

variable "secondary_region" {
  description = "Different AWS region hosting the Global Database secondary."
  type        = string

  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "primary_region and secondary_region must be different."
  }
}

variable "primary_vpc_id" {
  description = "Network-team VPC ID in the primary region. Database subnets are selected by tier=database unless explicit subnet IDs are supplied."
  type        = string
}

variable "secondary_vpc_id" {
  description = "Network-team VPC ID in the secondary region. Database subnets are selected by tier=database unless explicit subnet IDs are supplied."
  type        = string
}

variable "primary_database_subnet_ids" {
  description = "Optional explicit primary database subnet IDs. Leave empty to discover subnets in primary_vpc_id tagged tier=database."
  type        = set(string)
  default     = []
}

variable "secondary_database_subnet_ids" {
  description = "Optional explicit secondary database subnet IDs. Leave empty to discover subnets in secondary_vpc_id tagged tier=database."
  type        = set(string)
  default     = []
}

variable "primary_eks_security_group_ids" {
  description = "EKS security groups permitted to connect to PostgreSQL in the primary VPC."
  type        = set(string)

  validation {
    condition     = length(var.primary_eks_security_group_ids) > 0
    error_message = "At least one primary EKS security group ID is required."
  }
}

variable "secondary_eks_security_group_ids" {
  description = "EKS security groups permitted to connect to PostgreSQL in the secondary VPC."
  type        = set(string)

  validation {
    condition     = length(var.secondary_eks_security_group_ids) > 0
    error_message = "At least one secondary EKS security group ID is required."
  }
}

variable "eks_iam_role_names" {
  description = "Existing IAM role names used by EKS workloads; each is granted rds-db:connect to the configured IAM database user in both regions."
  type        = set(string)

  validation {
    condition     = length(var.eks_iam_role_names) > 0
    error_message = "At least one EKS IAM role name is required."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_$]{0,62}$", var.database_name))
    error_message = "database_name must be a valid 1-63 character PostgreSQL database identifier."
  }
}

variable "master_username" {
  description = "Administrative PostgreSQL username. The password is generated and managed by RDS in Secrets Manager."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.master_username)) && !contains(["admin", "postgres", "root"], lower(var.master_username))
    error_message = "master_username must be a valid PostgreSQL identifier and must not be admin, postgres, or root."
  }
}

variable "iam_database_username" {
  description = "PostgreSQL login provisioned with rds_iam for EKS workload authentication. Application/database grants are managed separately."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.iam_database_username))
    error_message = "iam_database_username must be a valid PostgreSQL identifier."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version; primary and secondary are kept on this same version."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Aurora DB instance class used in both regions."
  type        = string
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  description = "Number of instances in the primary region. At least two provides regional writer failover."
  type        = number
  default     = 2

  validation {
    condition     = var.primary_instance_count >= 2 && var.primary_instance_count <= 15 && floor(var.primary_instance_count) == var.primary_instance_count
    error_message = "primary_instance_count must be a whole number from 2 to 15."
  }
}

variable "secondary_instance_count" {
  description = "Pre-provisioned instances in the secondary region, ready to serve after Global Database failover."
  type        = number
  default     = 2

  validation {
    condition     = var.secondary_instance_count >= 1 && var.secondary_instance_count <= 15 && floor(var.secondary_instance_count) == var.secondary_instance_count
    error_message = "secondary_instance_count must be a whole number from 1 to 15."
  }
}

variable "backup_retention_period" {
  description = "Automated backup retention in days."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period must be a whole number from 7 to 35 days."
  }
}

variable "log_retention_days" {
  description = "CloudWatch PostgreSQL log retention."
  type        = number
  default     = 365
}
