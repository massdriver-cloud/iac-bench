variable "role" {
  description = "Whether this regional cluster is the writable primary or the read-only secondary of the global database."
  type        = string

  validation {
    condition     = contains(["primary", "secondary"], var.role)
    error_message = "role must be \"primary\" or \"secondary\"."
  }
}

variable "name_prefix" {
  description = "Prefix for all resource names, e.g. \"checkout-prod\"."
  type        = string
}

variable "environment" {
  description = "Environment name (staging or prod). Used for tagging only."
  type        = string
}

variable "vpc_name" {
  description = "Value of the Name tag of the network team's VPC in this region (e.g. apps-prod)."
  type        = string
}

variable "global_cluster_identifier" {
  description = "Identifier of the Aurora global cluster this regional cluster joins."
  type        = string
}

variable "primary_region" {
  description = "Region of the writable primary cluster. Secondary clusters replicate from it."
  type        = string
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version. Must be identical in every region of the global cluster."
  type        = string
}

variable "database_name" {
  description = "Initial database name. Only set on the primary cluster."
  type        = string
  default     = null
}

variable "master_username" {
  description = "Master username. Only set on the primary cluster; the password is managed by Secrets Manager."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "Instance class for every Aurora instance in this cluster."
  type        = string
}

variable "instance_count" {
  description = "Number of Aurora instances in this regional cluster. At least 2 so the region survives an AZ failure."
  type        = number
}

variable "allowed_cidr_blocks" {
  description = "Additional IPv4 CIDRs allowed to reach PostgreSQL on 5432. The VPC CIDR is always allowed."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach PostgreSQL on 5432."
  type        = list(string)
}

variable "backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
}

variable "preferred_backup_window" {
  description = "Daily UTC window for automated backups."
  type        = string
}

variable "preferred_maintenance_window" {
  description = "Weekly UTC window for maintenance."
  type        = string
}

variable "deletion_protection" {
  description = "Whether the cluster is protected from deletion."
  type        = bool
}

variable "kms_deletion_window_days" {
  description = "Waiting period before a KMS key is deleted."
  type        = number
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention in days."
  type        = number
}

variable "replication_lag_alarm_threshold_ms" {
  description = "Alarm threshold for AuroraGlobalDBReplicationLag in milliseconds (secondary only). This is the RPO monitor."
  type        = number
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic for alarm notifications."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
