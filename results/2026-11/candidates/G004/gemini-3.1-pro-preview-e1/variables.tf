variable "primary_region" {
  type        = string
  description = "Primary AWS region for the Aurora Global Database"
}

variable "secondary_region" {
  type        = string
  description = "Secondary AWS region for the Aurora Global Database"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., staging, prod)"
}

variable "service_name" {
  type        = string
  description = "Name of the service using this database"
}

variable "db_name" {
  type        = string
  description = "Name of the default database to create"
  default     = "appdb"
}

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL engine version"
  default     = "15.3"
}

variable "instance_class" {
  type        = string
  description = "Instance class for Aurora instances"
  default     = "db.r6g.large"
}

variable "primary_instance_count" {
  type        = number
  description = "Number of instances in the primary region (should be >= 2 for prod)"
  default     = 2
}

variable "secondary_instance_count" {
  type        = number
  description = "Number of instances in the secondary region (can be 1 for pilot light)"
  default     = 1
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Whether to skip final snapshot when destroying"
  default     = false
}

variable "backup_retention_period" {
  type        = number
  description = "Number of days to retain backups"
  default     = 14
}
