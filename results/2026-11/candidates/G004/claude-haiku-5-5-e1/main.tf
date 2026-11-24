data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  name_prefix   = "${var.service_name}-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  vpc_name      = "apps-${var.environment}"

  tags = merge(var.additional_tags, {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "opentofu"
    Module      = "aurora-global-postgres"
  })
}

# ---------------------------------------------------------------------------
# Global cluster: the replication envelope spanning both regions. Writes go to
# whichever regional cluster is currently primary.
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  provider = aws

  global_cluster_identifier = local.name_prefix
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be different regions."
    }
  }
}

# ---------------------------------------------------------------------------
# Regional clusters. Each is built by the same submodule with its own provider.
#
# Ordering: the secondary takes its global_cluster_identifier from the
# primary's cluster resource, so it is created only after the primary has
# joined the global cluster. This is a data dependency, not depends_on, so
# the secondary's data sources (VPC and subnet lookups) are still read at
# plan time.
# ---------------------------------------------------------------------------

module "primary" {
  source = "./modules/aurora_region"

  providers = {
    aws = aws
  }

  role                                = "primary"
  name_prefix                         = local.name_prefix
  environment                         = var.environment
  vpc_name                            = local.vpc_name
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  primary_region                      = var.primary_region
  engine_version                      = var.engine_version
  database_name                       = local.database_name
  master_username                     = var.master_username
  instance_class                      = var.instance_class
  instance_count                      = var.instance_count
  allowed_cidr_blocks                 = var.allowed_cidr_blocks
  allowed_security_group_ids          = var.allowed_security_group_ids
  backup_retention_days               = var.backup_retention_days
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  deletion_protection                 = var.deletion_protection
  kms_deletion_window_days            = var.kms_deletion_window_days
  performance_insights_retention_days = var.performance_insights_retention_days
  replication_lag_alarm_threshold_ms  = var.replication_lag_alarm_threshold_ms
  alarm_sns_topic_arn                 = var.alarm_sns_topic_arn
  tags                                = local.tags
}

module "secondary" {
  source = "./modules/aurora_region"

  providers = {
    aws = aws.secondary
  }

  role                                = "secondary"
  name_prefix                         = local.name_prefix
  environment                         = var.environment
  vpc_name                            = local.vpc_name
  global_cluster_identifier           = module.primary.global_cluster_identifier
  primary_region                      = var.primary_region
  engine_version                      = var.engine_version
  database_name                       = null
  master_username                     = null
  instance_class                      = var.instance_class
  instance_count                      = var.instance_count
  allowed_cidr_blocks                 = var.allowed_cidr_blocks
  allowed_security_group_ids          = var.allowed_security_group_ids
  backup_retention_days               = var.backup_retention_days
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  deletion_protection                 = var.deletion_protection
  kms_deletion_window_days            = var.kms_deletion_window_days
  performance_insights_retention_days = var.performance_insights_retention_days
  replication_lag_alarm_threshold_ms  = var.replication_lag_alarm_threshold_ms
  alarm_sns_topic_arn                 = var.alarm_sns_topic_arn
  tags                                = local.tags
}

# ---------------------------------------------------------------------------
# Application access. IAM database authentication means no static DB password
# reaches the services. The policy covers the app DB users on whichever
# cluster is primary, so it keeps working after a failover.
# ---------------------------------------------------------------------------

locals {
  connect_resources = flatten([
    for user in var.app_db_users : [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.primary.cluster_resource_id}/${user}",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.secondary.cluster_resource_id}/${user}",
    ]
  ])
}

data "aws_iam_policy_document" "app_connect" {
  count = length(var.app_db_users) > 0 ? 1 : 0

  statement {
    sid       = "IamDatabaseConnect"
    actions   = ["rds-db:connect"]
    resources = local.connect_resources
  }
}

resource "aws_iam_policy" "app_connect" {
  count = length(var.app_db_users) > 0 ? 1 : 0

  name        = "${local.name_prefix}-aurora-connect"
  description = "IAM database authentication to ${local.name_prefix} Aurora (both regions)."
  policy      = data.aws_iam_policy_document.app_connect[0].json
}

resource "aws_iam_role_policy_attachment" "app_connect" {
  for_each = length(var.app_db_users) > 0 ? toset(var.app_iam_role_names) : toset([])

  role       = each.value
  policy_arn = aws_iam_policy.app_connect[0].arn
}
