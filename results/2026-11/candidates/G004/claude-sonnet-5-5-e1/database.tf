# ---------------------------------------------------------------------------
# Aurora Global Database: continuous storage-level replication to the
# secondary region (typically ~1s lag) gives the low RPO; the secondary
# region's running instances give the minutes-scale RTO when it is promoted
# (managed failover / switchover, or detach-and-promote in an outage).
#
# Applications authenticate with IAM database authentication (their EKS IAM
# roles); the master credential is managed by RDS in Secrets Manager and is
# for administrators only.
#
# NOTE: after a failover/switchover the roles of the two clusters swap in AWS.
# Reconcile the OpenTofu state (import/state move) before applying further
# changes, rather than letting it "fix" the topology back.
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.identifier
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = "${local.identifier}-${var.primary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = var.engine_version
  database_name             = var.database_name
  port                      = local.port

  master_username               = "dbadmin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.identifier}-${var.primary_region}-final"

  allow_major_version_upgrade = false

  lifecycle {
    # Changes after a global failover/switchover.
    ignore_changes = [global_cluster_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  for_each = toset(local.instance_ix)

  identifier         = "${local.identifier}-${var.primary_region}-${each.value}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  instance_class     = var.instance_class
  promotion_tier     = tonumber(each.value) == 0 ? 0 : 1

  db_subnet_group_name = aws_db_subnet_group.primary.name
  publicly_accessible  = false

  auto_minor_version_upgrade            = false
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  copy_tags_to_snapshot                 = true

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.identifier}-${var.secondary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = var.engine_version
  port                      = local.port
  source_region             = var.primary_region

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.identifier}-${var.secondary_region}-final"

  allow_major_version_upgrade = false

  lifecycle {
    ignore_changes = [global_cluster_identifier, replication_source_identifier]
  }

  # The secondary can only be added once the primary has a writer.
  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  for_each = toset(local.instance_ix)

  identifier         = "${local.identifier}-${var.secondary_region}-${each.value}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class
  promotion_tier     = tonumber(each.value) == 0 ? 0 : 1

  db_subnet_group_name = aws_db_subnet_group.secondary.name
  publicly_accessible  = false

  auto_minor_version_upgrade            = false
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  copy_tags_to_snapshot                 = true

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}

# ---------------------------------------------------------------------------
# Replication lag alarm (the RPO signal)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.identifier}-global-replication-lag"
  alarm_description   = "Cross-region replication lag for ${local.identifier} exceeds the RPO budget."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.replication_lag_alarm_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
}
