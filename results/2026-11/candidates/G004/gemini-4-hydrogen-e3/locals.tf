locals {
  name_prefix            = "${var.service_name}-${var.environment}"
  default_iam_db_user    = "${replace(var.service_name, "-", "_")}_app"
  iam_database_users     = length(var.iam_database_users) > 0 ? var.iam_database_users : [local.default_iam_db_user]
  engine_version         = data.aws_rds_engine_version.primary.version
  parameter_group_family = data.aws_rds_engine_version.primary.parameter_group_family
  account_id             = data.aws_caller_identity.current.account_id
  partition              = data.aws_partition.current.partition
}
