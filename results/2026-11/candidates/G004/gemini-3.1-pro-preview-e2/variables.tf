variable "environment" {
  type        = string
  description = "Deployment environment, e.g., 'staging' or 'prod'."
}

variable "service_name" {
  type        = string
  description = "Name of the service that owns the database."
}

variable "database_name" {
  type        = string
  description = "Name of the initial PostgreSQL database to create."
}

variable "master_username" {
  type        = string
  description = "Master username for the database."
}

variable "primary_region" {
  type        = string
  description = "AWS region for the primary database cluster."
}

variable "secondary_region" {
  type        = string
  description = "AWS region for the secondary database cluster."
}

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL engine version."
  default     = "15.4"
}

variable "instance_class" {
  type        = string
  description = "Instance class for the Aurora cluster instances."
  default     = "db.r6g.large"
}

variable "instance_count" {
  type        = number
  description = "Number of cluster instances to launch in each region."
  default     = 1
}
