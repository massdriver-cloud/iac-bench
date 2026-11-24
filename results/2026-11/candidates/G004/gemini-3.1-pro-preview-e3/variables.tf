variable "primary_region" {
  type        = string
  description = "Primary AWS region for the global database"
}

variable "secondary_region" {
  type        = string
  description = "Secondary AWS region for the global database"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., staging, prod)"
}

variable "service_name" {
  type        = string
  description = "Name of the service (used for naming and db_name)"
}

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL engine version"
  default     = "15.4"
}

variable "instance_class" {
  type        = string
  description = "Instance class for the Aurora cluster instances"
  default     = "db.r6g.large"
}
