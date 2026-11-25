data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  env_short = trimprefix(var.environment, "apps-")
  vpc_name  = "apps-${local.env_short}"

  name_prefix          = "${var.service_name}-${local.env_short}"
  global_cluster_id    = "${local.name_prefix}-global"
  primary_cluster_id   = "${local.name_prefix}-${var.primary_region}"
  secondary_cluster_id = "${local.name_prefix}-${var.secondary_region}"

  database_name         = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  db_iam_users          = distinct(coalesce(var.db_iam_users, [local.database_name]))
  db_readonly_iam_users = distinct(coalesce(var.db_readonly_iam_users, ["${local.database_name}_readonly"]))

  is_serverless          = var.instance_class == "db.serverless"
  cloudwatch_log_exports = ["postgresql", "iam-db-auth-error", "instance"]

  default_tags = {
    service             = var.service_name
    environment         = local.env_short
    data-classification = "customer-and-payment"
    managed-by          = "opentofu"
  }

  tags = merge(local.default_tags, var.tags)
}
