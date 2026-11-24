variable "name" {
  description = "Base name (<service>-<environment>) for regional resources."
  type        = string
}

variable "region" {
  description = "Region this instance of the module is deployed to (must match the provider passed in)."
  type        = string
}

variable "account_id" {
  description = "AWS account ID."
  type        = string
}

variable "partition" {
  description = "AWS partition."
  type        = string
}

variable "cluster_identifier" {
  description = "Identifier of the Aurora cluster that will live in this region."
  type        = string
}

variable "engine" {
  description = "Database engine."
  type        = string
}

variable "engine_version" {
  description = "Database engine version."
  type        = string
}

variable "instance_class" {
  description = "Instance class the cluster's instances will use."
  type        = string
}

variable "vpc_name" {
  description = "Name tag of the VPC to place the database in."
  type        = string
}

variable "port" {
  description = "Database port."
  type        = number
}

variable "client_security_group_ids" {
  description = "Security groups allowed to connect to the database in this region."
  type        = list(string)
}

variable "parameter_group_family" {
  description = "Cluster parameter group family, e.g. aurora-postgresql16."
  type        = string
}

variable "cluster_parameters" {
  description = "Cluster parameters to set."
  type = list(object({
    name         = string
    value        = string
    apply_method = string
  }))
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for database logs."
  type        = number
}

variable "replication_lag_alarm_seconds" {
  description = "Replication lag threshold for the alarm, in seconds."
  type        = number
}

variable "alarm_sns_topic_arns" {
  description = "SNS topics (in this region) notified by the alarm."
  type        = list(string)
}
