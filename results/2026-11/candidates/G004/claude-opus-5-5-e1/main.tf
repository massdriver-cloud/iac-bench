locals {
  name          = "${var.service_name}-${var.environment}"
  engine        = "aurora-postgresql"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))

  common_tags = merge(var.tags, {
    Service            = var.service_name
    Environment        = var.environment
    ManagedBy          = "opentofu"
    DataClassification = "customer-payment"
  })
}

data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Master credentials (break-glass only; apps use IAM auth). Stored in Secrets
# Manager, replicated to the secondary region so it is reachable after a
# regional failure.
# ---------------------------------------------------------------------------
resource "random_password" "master" {
  length           = 40
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  name                    = "rds/${local.name}/master"
  description             = "Master credentials for Aurora global database ${local.name}"
  kms_key_id              = module.primary.kms_key_arn
  recovery_window_in_days = 30

  replica {
    region     = var.secondary_region
    kms_key_id = module.secondary.kms_key_arn
  }
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    engine   = "postgres"
    username = var.master_username
    password = random_password.master.result
    dbname   = local.database_name
    port     = 5432
    # Global writer endpoint follows the writer across regions on failover.
    host = aws_rds_global_cluster.this.endpoint
  })
}

# ---------------------------------------------------------------------------
# Enhanced monitoring role (IAM is global; shared by both regions).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${local.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------------------------
# Aurora Global Database: storage-level replication (typically <1s lag, RPO
# of seconds) and managed cross-region failover/switchover (RTO of minutes).
# ---------------------------------------------------------------------------
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = local.engine
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = true

  lifecycle {
    ignore_changes = [engine_version, database_name]
  }
}

module "primary" {
  source = "./modules/regional_cluster"

  name                         = local.name
  environment                  = var.environment
  is_primary                   = true
  global_cluster_identifier    = aws_rds_global_cluster.this.id
  engine                       = local.engine
  engine_version               = var.engine_version
  database_name                = local.database_name
  master_username              = var.master_username
  master_password              = random_password.master.result
  instance_class               = var.instance_class
  instance_count               = var.instances_per_region
  backup_retention_days        = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  allowed_security_group_ids   = var.allowed_security_group_ids.primary
  allowed_cidr_blocks          = var.allowed_cidr_blocks.primary
  monitoring_role_arn          = aws_iam_role.monitoring.arn
  skip_final_snapshot          = var.skip_final_snapshot
  replication_lag_threshold_ms = var.replication_lag_threshold_ms
  alarm_actions                = var.alarm_actions.primary

  wait_for = [aws_iam_role_policy_attachment.monitoring.id]
}

module "secondary" {
  source = "./modules/regional_cluster"
  providers = {
    aws = aws.secondary
  }

  name                      = local.name
  environment               = var.environment
  is_primary                = false
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = local.engine
  engine_version            = var.engine_version
  database_name             = local.database_name
  master_username           = var.master_username
  # Same size as the primary: after a failover it must carry the full load.
  instance_class               = var.instance_class
  instance_count               = var.instances_per_region
  backup_retention_days        = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  allowed_security_group_ids   = var.allowed_security_group_ids.secondary
  allowed_cidr_blocks          = var.allowed_cidr_blocks.secondary
  monitoring_role_arn          = aws_iam_role.monitoring.arn
  skip_final_snapshot          = var.skip_final_snapshot
  replication_lag_threshold_ms = var.replication_lag_threshold_ms
  alarm_actions                = var.alarm_actions.secondary

  # The secondary can only join the global cluster once the primary has a writer.
  wait_for = concat([aws_iam_role_policy_attachment.monitoring.id], module.primary.instance_ids)
}

# ---------------------------------------------------------------------------
# IAM database authentication: attach this policy to service IAM roles (e.g.
# EKS pod identity / IRSA roles). Covers both regions so it keeps working
# after a failover.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "connect" {
  count = length(var.iam_db_users) > 0 ? 1 : 0

  statement {
    sid     = "RdsIamConnect"
    actions = ["rds-db:connect"]
    resources = flatten([
      for c in [module.primary, module.secondary] : [
        for u in var.iam_db_users :
        "arn:${data.aws_partition.current.partition}:rds-db:${c.region}:${c.account_id}:dbuser:${c.cluster_resource_id}/${u}"
      ]
    ])
  }
}

resource "aws_iam_policy" "connect" {
  count = length(var.iam_db_users) > 0 ? 1 : 0

  name        = "${local.name}-rds-connect"
  description = "IAM database authentication to ${local.name} in both regions"
  policy      = data.aws_iam_policy_document.connect[0].json
}
