variable "name" {
  type        = string
  description = "Base name for all regional resources."
}

variable "vpc_tags" {
  type        = map(string)
  description = "Tags identifying the VPC the database is placed in."
}

variable "subnet_tags" {
  type        = map(string)
  description = "Tags identifying the private database subnets inside the VPC."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = null
  description = "CIDR blocks allowed to connect to the database port. Null falls back to the VPC CIDR block."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security group IDs allowed to connect to the database port."
}

variable "cluster_parameters" {
  type        = map(string)
  default     = {}
  description = "Parameters for the RDS cluster parameter group."
}

variable "parameter_group_family" {
  type        = string
  description = "Parameter group family, e.g. aurora-postgresql16."
}

variable "port" {
  type        = number
  default     = 5432
  description = "Database port."
}
