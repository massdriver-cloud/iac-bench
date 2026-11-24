# ---------------------------------------------------------------------------
# Aurora Global Database: one global cluster, a writer cluster in the primary
# region and a standby cluster in the secondary region. Storage-level
# replication keeps the standby within ~1s of the primary (RPO of seconds);
# managed failover/switchover promotes it in about a minute (RTO of minutes).
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = local.name
  engine                    = local.engine
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    # Minor-version upgrades are rolled through the member clusters; keep the
    # global cluster from fighting the engine over the reported version.
    ignore_changes = [engine_version]
  }
}

# --- Primary (writer) cluster ----------------------------------------------

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = local.name
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = local.engine
  engine_version            = var.engine_version
  engine_mode               = "provisioned"
  port                      = local.port

  # Break-glass credentials are generated and stored in Secrets Manager under
  # our KMS key; nobody ever sees or supplies a password. Applications use IAM.
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  enabled_cloudwatch_logs_exports = local.log_exports

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = local.backup_window
  preferred_maintenance_window = local.maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-final"
  apply_immediately         = var.apply_immediately

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    # After a managed failover the roles swap; keep OpenTofu from trying to
    # "fix" the replication link. Fail back with switchover-global-cluster.
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.primary_instance_count

  identifier         = "${local.name}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.primary.name
  publicly_accessible  = false

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_days
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn

  auto_minor_version_upgrade   = true
  preferred_maintenance_window = local.maintenance_window
  copy_tags_to_snapshot        = true
  apply_immediately            = var.apply_immediately

  # Writer is promoted from tier 0/1 first; keep the first instance preferred.
  promotion_tier = count.index

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}

# --- Secondary (standby) cluster -------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.name
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = local.engine
  engine_version            = var.engine_version
  engine_mode               = "provisioned"
  port                      = local.port

  # Credentials, database name and IAM auth are inherited through the global
  # cluster; they cannot be set on a secondary.
  kms_key_id = aws_kms_key.secondary.arn

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  enabled_cloudwatch_logs_exports = local.log_exports

  enable_global_write_forwarding = var.enable_global_write_forwarding

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = local.backup_window
  preferred_maintenance_window = local.maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-final"
  apply_immediately         = var.apply_immediately

  # The secondary can only join once the primary has a running writer.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.name}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.secondary.name
  publicly_accessible  = false

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_days
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn

  auto_minor_version_upgrade   = true
  preferred_maintenance_window = local.maintenance_window
  copy_tags_to_snapshot        = true
  apply_immediately            = var.apply_immediately

  promotion_tier = count.index

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}
