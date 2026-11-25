variable "service" {
  description = "Unique service slug, used in RDS identifiers."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,24}$", var.service))
    error_message = "Use 2-25 lowercase letters and digits, starting with a letter."
  }
}
variable "environment" {
  type    = string
  default = "prod"
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Choose staging or prod."
  }
}
variable "locations" {
  description = "Regional deployment coordinates, existing EKS client SG and existing alarm SNS topic in each region."
  type        = object({ primary = object({ region = string, client_sg = string, alarm_topic = string }), secondary = object({ region = string, client_sg = string, alarm_topic = string }) })
  validation {
    condition     = var.locations.primary.region != var.locations.secondary.region && alltrue([for site in values(var.locations) : can(regex("^us-(east|west)-[12]$", site.region)) && startswith(site.alarm_topic, "arn:aws:sns:${site.region}:")])
    error_message = "Specify distinct commercial US regions and regional SNS topic ARNs."
  }
}
variable "client_roles" {
  description = "Map existing EKS workload IAM role names (not ARNs) to non-admin PostgreSQL login names."
  type        = map(string)
  validation {
    condition     = length(var.client_roles) > 0 && alltrue([for u in values(var.client_roles) : can(regex("^[a-z][a-z0-9_]{0,62}$", u)) && !contains(["dbadmin", "postgres", "rdsadmin"], u)])
    error_message = "Provide at least one workload role and a simple non-admin database login name."
  }
}
variable "engine_version" {
  description = "Exact Aurora PostgreSQL 16 minor version available for Global Database in both regions. Coordinate upgrades across regions."
  type        = string
  default     = "16.9"
  validation {
    condition     = can(regex("^16\\.[0-9]+$", var.engine_version))
    error_message = "Select an Aurora PostgreSQL 16 minor release."
  }
}
variable "instance_class" {
  type    = string
  default = "db.r7g.large"
}
locals {
  name = "${var.service}-${var.environment}"
  tags = { Service = var.service, Environment = var.environment, ManagedBy = "OpenTofu" }
}
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = ">= 5.80, < 7.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
provider "aws" {
  region = var.locations.primary.region
  default_tags { tags = local.tags }
}
provider "aws" {
  alias  = "secondary"
  region = var.locations.secondary.region
  default_tags { tags = local.tags }
}
