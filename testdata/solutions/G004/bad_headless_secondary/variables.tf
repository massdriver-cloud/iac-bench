variable "name" {
  description = "Database name, used for the global cluster and both regional clusters."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}$", var.name))
    error_message = "Use 2-41 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment whose network the database joins: the VPC named apps-<environment> in each region."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Environment must be staging or prod."
  }
}

variable "primary_region" {
  description = "Region that takes writes."
  type        = string
}

variable "secondary_region" {
  description = "Region that holds the standby cluster and takes over if the primary region fails."
  type        = string
  validation {
    condition     = var.secondary_region != var.primary_region
    error_message = "The secondary region must differ from the primary region."
  }
}

variable "client_security_group_ids" {
  description = "Security groups allowed to connect on 5432, per region (for example each EKS cluster's node security group)."
  type = object({
    primary   = optional(list(string), [])
    secondary = optional(list(string), [])
  })
  default = {}
}

variable "instance_class" {
  description = "Instance class for every instance in both regions."
  type        = string
  default     = "db.r7g.large"
}

variable "instances_per_region" {
  description = "Instances per region: a writer plus readers in the primary, and the standby's readers. At least two, so each region survives losing an availability zone."
  type        = number
  default     = 2
  validation {
    condition     = var.instances_per_region >= 2
    error_message = "Use at least two instances per region."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL version. Upgrade through the global cluster."
  type        = string
  default     = "17.5"
}

variable "backup_retention_days" {
  description = "Days of automated backups and point-in-time recovery."
  type        = number
  default     = 14
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Retain backups for 7 to 35 days."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the clusters. Turn off only to retire the database."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Destroy without a final snapshot. Leave false for any database holding real data."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
