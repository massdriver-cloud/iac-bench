###############################################################################
# The two regional clusters that make up the global database.
#
# Creation order matters and is pinned explicitly: global cluster → primary
# cluster (+ instances) → DR cluster (+ instances). Destruction follows the
# reverse order, which is also the order Aurora requires (DR member removed
# before the primary, primary before the global cluster).
###############################################################################

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier = local.primary_cluster_identifier

  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = local.engine
  # Members are pinned to the global cluster's version, not the variable, so
  # the two regions can never drift onto different engine versions.
  engine_version = aws_rds_global_cluster.this.engine_version

  # Break-glass access only. RDS generates, stores, and rotates the master
  # password in Secrets Manager, so it never appears in OpenTofu state, plans,
  # or CI logs. Services connect with IAM database authentication instead.
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = local.primary_kms_key_arn

  database_name = var.database_name
  port          = var.port

  storage_encrypted = true
  kms_key_id        = local.primary_kms_key_arn

  iam_database_authentication_enabled = var.enable_iam_database_auth

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]

  # Point-in-time recovery. Logical corruption replicates to the DR region
  # just as faithfully as good data, so PITR is the recovery path of record.
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports = local.log_exports

  deletion_protection       = local.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier
  apply_immediately         = false

  tags = {
    Name = local.primary_cluster_identifier
  }

  # Own the log groups before the cluster is created, so RDS adopts them
  # (with their retention) instead of auto-creating never-expiring ones.
  depends_on = [
    aws_cloudwatch_log_group.primary_postgresql,
    aws_cloudwatch_log_group.primary_audit,
  ]
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier = local.secondary_cluster_identifier

  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version

  # The DR cluster is a full replica of the primary: cluster-level
  # configuration (master credentials, IAM auth, database name, port) is
  # inherited through the global database. Only region-local resources are
  # wired here — subnet group, security groups, an identical parameter group,
  # and log export into the region's CloudWatch.
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]

  enabled_cloudwatch_logs_exports = local.log_exports

  deletion_protection = local.deletion_protection

  # A global secondary cannot take final snapshots, and it only ever holds a
  # replica of data the primary already has — the primary's final snapshot
  # covers it. This keeps teardown of the DR member clean.
  skip_final_snapshot = true

  apply_immediately = false

  tags = {
    Name = local.secondary_cluster_identifier
  }

  # A region can only join a global database once the primary exists with
  # healthy instances, so the join waits for them.
  depends_on = [
    aws_rds_cluster.primary,
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary_postgresql,
    aws_cloudwatch_log_group.secondary_audit,
  ]
}
