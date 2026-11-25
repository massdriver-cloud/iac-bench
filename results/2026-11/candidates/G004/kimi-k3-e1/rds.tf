# -----------------------------------------------------------------------------
# Aurora global database: one writer cluster in the primary region and one
# warm standby cluster in the secondary region. Storage-level replication
# between regions typically lags well under a second (RPO of a few seconds
# in the worst case), and a managed switchover promotes the secondary to
# writer in about a minute (RTO of minutes). See the `switchover_command`
# output and the README runbook.
# -----------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = var.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

# --- Primary (writer) ---------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  cluster_identifier = local.primary_cluster_identifier

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  engine_mode    = "provisioned"

  global_cluster_identifier = aws_rds_global_cluster.this.id
  port                      = var.port

  # The master password is generated and managed by RDS in Secrets Manager;
  # it never appears in this configuration or in state.
  master_username             = var.master_username
  manage_master_user_password = true

  db_subnet_group_name            = module.primary_region.subnet_group_name
  vpc_security_group_ids          = [module.primary_region.security_group_id]
  db_cluster_parameter_group_name = module.primary_region.cluster_parameter_group_name

  storage_encrypted = true
  kms_key_id        = module.primary_region.kms_key_arn

  # EKS services authenticate with their IAM roles and short-lived tokens
  # instead of static passwords.
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${local.primary_cluster_identifier}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  apply_immediately   = var.apply_immediately
  deletion_protection = var.deletion_protection
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier         = "${local.primary_cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = aws_rds_global_cluster.this.engine
  engine_version     = aws_rds_global_cluster.this.engine_version

  publicly_accessible = false
  promotion_tier      = count.index

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = module.primary_region.kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = local.monitoring_role_arn

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}

# --- Secondary (standby) -------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier = local.secondary_cluster_identifier

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  engine_mode    = "provisioned"

  global_cluster_identifier = aws_rds_global_cluster.this.id
  source_region             = var.primary_region

  # Master credentials, database name and port are inherited from the
  # global cluster and must not be repeated here.

  db_subnet_group_name            = module.secondary_region.subnet_group_name
  vpc_security_group_ids          = [module.secondary_region.security_group_id]
  db_cluster_parameter_group_name = module.secondary_region.cluster_parameter_group_name

  # KMS keys are region-scoped, so the standby cluster is encrypted with its
  # own customer managed key in the secondary region.
  storage_encrypted = true
  kms_key_id        = module.secondary_region.kms_key_arn

  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  # Snapshots are taken from the primary; the replica is disposable.
  skip_final_snapshot = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  apply_immediately   = var.apply_immediately
  deletion_protection = var.deletion_protection

  # AWS requires the writer cluster to be up and running (with at least one
  # instance) before a secondary region may join the global cluster.
  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary

  count = var.secondary_instance_count

  identifier         = "${local.secondary_cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = var.instance_class
  engine             = aws_rds_global_cluster.this.engine
  engine_version     = aws_rds_global_cluster.this.engine_version

  publicly_accessible = false
  promotion_tier      = count.index

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = module.secondary_region.kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = local.monitoring_role_arn

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}
