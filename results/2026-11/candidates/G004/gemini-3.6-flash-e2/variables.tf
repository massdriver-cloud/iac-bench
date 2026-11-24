variable "service_name" {
  description = "Name of the service owning the database (e.g., checkout, payment)."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., prod, staging)."
  type        = string
  default     = "prod"
}

variable "vpc_name" {
  description = "Name of the VPC to locate via data source. Defaults to apps-<environment> if omitted."
  type        = string
  default     = null
}

variable "subnet_tag_key" {
  description = "Tag key used to filter private database subnets."
  type        = string
  default     = "tier"
}

variable "subnet_tag_value" {
  description = "Tag value used to filter private database subnets."
  type        = string
  default     = "database"
}

variable "primary_region" {
  description = "AWS region for the primary Aurora cluster."
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "AWS region for the secondary Aurora cluster (DR/Failover)."
  type        = string
  default     = "us-west-2"
}

variable "database_name" {
  description = "Name of the default PostgreSQL database. Derived from service_name if omitted."
  type        = string
  default     = null
}

variable "master_username" {
  description = "Master database username."
  type        = string
  default     = "dbadmin"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "15.4"
}

variable "instance_class" {
  description = "Instance class for Aurora database cluster instances."
  type        = string
  default     = "db.r6g.xlarge"
}

variable "primary_instance_count" {
  description = "Number of database instances in the primary region cluster."
  type        = number
  default     = 2
}

variable "secondary_instance_count" {
  description = "Number of database instances in the secondary region cluster."
  type        = number
  default     = 2
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups."
  type        = number
  default     = 30
}

variable "deletion_protection" {
  description = "If true, deletion protection will be enabled on the database clusters."
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "List of additional CIDR blocks allowed to connect to PostgreSQL (port 5432)."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access the primary database cluster."
  type        = list(string)
  default     = []
}

variable "secondary_allowed_security_group_ids" {
  description = "List of security group IDs allowed to access the secondary database cluster."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Map of resource tags to apply to all managed resources."
  type        = map(string)
  default     = {}
}
