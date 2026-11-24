variable "service" {
  description = "Short service name used in RDS identifiers."
  type        = string
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,24}[a-z0-9])?$", var.service)) && !can(regex("--", var.service))
    error_message = "Use up to 26 lower-case letters, digits and single interior hyphens, starting with a letter."
  }
}
variable "environment" {
  type    = string
  default = "prod"
  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "Use staging or prod."
  }
}
variable "primary_region" {
  type    = string
  default = "us-east-1"
}
variable "recovery_region" {
  type    = string
  default = "us-west-2"
}
variable "primary_client_security_group" {
  type        = string
  description = "Security group on authorized EKS pod or node ENIs in primary VPC."
}
variable "recovery_client_security_group" {
  type        = string
  description = "Security group on authorized EKS pod or node ENIs in recovery VPC."
}
variable "application_role_name" {
  type        = string
  description = "EKS workload IAM role (name, not ARN) used by the service in both regions."
}
variable "alarm_topic_primary" {
  type        = string
  description = "Existing monitored SNS topic ARN in primary region."
}
variable "alarm_topic_recovery" {
  type        = string
  description = "Existing monitored SNS topic ARN in recovery region."
}
variable "engine_version" {
  type        = string
  description = "Exact Aurora PostgreSQL Global Database release available in both regions."
  default     = "16.11"
  validation {
    condition     = can(regex("^16\\.[0-9]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "This module uses the aurora-postgresql16 parameter family."
  }
}
variable "instance_class" {
  type    = string
  default = "db.r6g.large"
}
locals {
  name = "${var.service}-${var.environment}"
  tags = { Service = var.service, Environment = var.environment, ManagedBy = "OpenTofu" }
}
