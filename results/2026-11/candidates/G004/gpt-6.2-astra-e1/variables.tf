variable "service" {
  description = "Short service slug, unique within the environment."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,23}$", var.service))
    error_message = "Use 2-24 lowercase letters or digits, beginning with a letter."
  }
}
variable "environment" {
  type    = string
  default = "prod"
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Select staging or prod."
  }
}
variable "primary_region" {
  type    = string
  default = "us-east-1"
}
variable "secondary_region" {
  type    = string
  default = "us-west-2"
}
variable "clients" {
  description = "Regional security groups attached to the service pods or their nodes."
  type        = object({ primary = string, secondary = string })
}
variable "application_role" {
  description = "Existing EKS workload IAM role name (not ARN)."
  type        = string
}
variable "bootstrap_password" {
  type        = string
  sensitive   = true
  ephemeral   = true
  description = "Break-glass cluster administrator password injected from a secret manager."
}
variable "password_version" {
  type        = number
  default     = 1
  description = "Increment when rotating the injected password."
}
variable "engine_version" {
  type        = string
  default     = "16.11"
  description = "Aurora PostgreSQL 16 minor version supported in both regions."
  validation {
    condition     = startswith(var.engine_version, "16.")
    error_message = "Parameter groups target Aurora PostgreSQL 16."
  }
}
variable "instance_class" {
  type    = string
  default = "db.r6g.large"
}
variable "alarm_topic_arn" {
  type        = string
  description = "Existing monitored SNS topic in the secondary region for replication alarms."
}
locals {
  name = "${var.service}-${var.environment}"
  tags = { Service = var.service, Environment = var.environment, ManagedBy = "OpenTofu" }
}
