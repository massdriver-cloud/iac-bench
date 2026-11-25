variable "environment" {
  description = "Environment name used in resource names and tags."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "service_name" {
  description = "Short service identifier used to name this database."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.service_name))
    error_message = "service_name must be 2-31 lowercase letters, digits, or hyphens and begin with a letter."
  }
}

variable "primary_region" {
  description = "US AWS region hosting the writable Aurora cluster."
  type        = string
  default     = "us-east-1"
  validation {
    condition     = startswith(var.primary_region, "us-")
    error_message = "primary_region must be a US AWS region."
  }
}

variable "secondary_region" {
  description = "Distinct US AWS region hosting the warm Global Database secondary."
  type        = string
  default     = "us-west-2"
  validation {
    condition     = var.secondary_region != var.primary_region && startswith(var.secondary_region, "us-")
    error_message = "secondary_region must be a US AWS region different from primary_region."
  }
}

variable "primary_vpc_id" {
  description = "Network-team VPC ID for the primary region."
  type        = string
}

variable "secondary_vpc_id" {
  description = "Network-team VPC ID for the secondary region."
  type        = string
}

variable "primary_database_subnet_ids" {
  description = "IDs of private primary-region subnets tagged tier=database, spanning at least two AZs."
  type        = list(string)
  validation {
    condition     = length(var.primary_database_subnet_ids) >= 2
    error_message = "At least two primary database subnets in distinct AZs are required."
  }
}

variable "secondary_database_subnet_ids" {
  description = "IDs of private secondary-region subnets tagged tier=database, spanning at least two AZs."
  type        = list(string)
  validation {
    condition     = length(var.secondary_database_subnet_ids) >= 2
    error_message = "At least two secondary database subnets in distinct AZs are required."
  }
}

variable "primary_eks_security_group_ids" {
  description = "EKS client security groups in the primary VPC permitted to connect on PostgreSQL port 5432."
  type        = list(string)
  validation {
    condition     = length(var.primary_eks_security_group_ids) > 0
    error_message = "At least one primary EKS client security group is required."
  }
}

variable "secondary_eks_security_group_ids" {
  description = "EKS client security groups in the secondary VPC permitted to connect on PostgreSQL port 5432."
  type        = list(string)
  validation {
    condition     = length(var.secondary_eks_security_group_ids) > 0
    error_message = "At least one secondary EKS client security group is required."
  }
}

variable "database_name" {
  description = "Initial PostgreSQL database created in the cluster."
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Initial database administrator username. Its generated password is managed by RDS in Secrets Manager."
  type        = string
  default     = "dbadmin"
}

variable "postgres_major_version" {
  description = "Aurora PostgreSQL parameter-group major version. Must match engine_version."
  type        = string
  default     = "16"
  validation {
    condition     = can(regex("^[0-9]+$", var.postgres_major_version))
    error_message = "postgres_major_version must be a numeric major version."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Keep postgres_major_version aligned with this value."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Aurora DB instance class."
  type        = string
  default     = "db.r6g.large"
}

variable "backup_window" {
  description = "Daily UTC backup window, in hh24:mi-hh24:mi format."
  type        = string
  default     = "03:00-03:30"
}

variable "maintenance_window" {
  description = "Weekly UTC maintenance window, in ddd:hh24:mi-ddd:hh24:mi format."
  type        = string
  default     = "sun:04:00-sun:04:30"
}

variable "log_retention_days" {
  description = "CloudWatch PostgreSQL log retention."
  type        = number
  default     = 90
  validation {
    condition     = contains([30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a supported CloudWatch Logs retention value."
  }
}

variable "iam_role_arns" {
  description = "EKS workload IAM role ARNs to grant database IAM authentication permissions. All roles must be in the same account."
  type        = list(string)
  default     = []
  validation {
    condition     = (length(var.iam_role_arns) == 0) == (length(var.iam_database_users) == 0)
    error_message = "Set iam_role_arns and iam_database_users together, or leave both empty."
  }
}

variable "iam_database_users" {
  description = "PostgreSQL IAM-authenticated database usernames. Create these users and grant database privileges separately."
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.iam_database_users) == length(toset(var.iam_database_users))
    error_message = "iam_database_users must not contain duplicates."
  }
}

variable "alarm_sns_topic_arns" {
  description = "Optional SNS topic ARNs in the secondary region notified when cross-region replication lag exceeds five seconds."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to resources."
  type        = map(string)
  default     = {}
}
