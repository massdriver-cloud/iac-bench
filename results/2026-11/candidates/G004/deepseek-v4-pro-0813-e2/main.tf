#
# Aurora PostgreSQL global database.
#
# A global database replicates storage-level writes from the primary cluster to
# the secondary region asynchronously with typical cross-region replication lag
# under one second. Promoting the secondary in a regional failover takes about
# a minute and only requires the platform team to run the documented failover
# command; no application data movement is needed.
#

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.global_cluster_identifier
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = local.primary_cluster_identifier
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  database_name   = var.database_name
  master_username = var.master_username
  master_password = data.aws_secretsmanager_random_password.master.random_password

  port                   = var.port
  db_subnet_group_name   = one(aws_db_subnet_group.primary[*].name)
  vpc_security_group_ids = aws_security_group.primary[*].id

  storage_encrypted = true
  kms_key_id        = var.create_kms_key ? one(aws_kms_key.primary[*].arn) : null

  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = "${local.primary_cluster_identifier}-final"
  apply_immediately               = var.apply_immediately

  tags = local.default_tags

  lifecycle {
    # The password is generated once and stored in Secrets Manager. Subsequent
    # reads of the Secrets Manager random-password data source must not rotate
    # the live cluster password.
    ignore_changes = [master_password]
  }
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_identifier
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  port                   = var.port
  db_subnet_group_name   = one(aws_db_subnet_group.secondary[*].name)
  vpc_security_group_ids = aws_security_group.secondary[*].id

  storage_encrypted = true
  kms_key_id        = var.create_kms_key ? one(aws_kms_key.secondary[*].arn) : null

  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = "${local.secondary_cluster_identifier}-final"
  apply_immediately               = var.apply_immediately

  tags = local.default_tags

  depends_on = [aws_rds_cluster.primary]
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.primary_instance_count

  identifier         = "${local.primary_cluster_identifier}-${count.index}"
  cluster_identifier = aws_rds_cluster.primary.id

  instance_class = var.instance_class
  engine         = aws_rds_cluster.primary.engine
  engine_version = aws_rds_cluster.primary.engine_version

  publicly_accessible        = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  performance_insights_enabled = var.enable_performance_insights

  tags = merge(
    local.default_tags,
    {
      Name = "${local.primary_cluster_identifier}-${count.index}"
    }
  )
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.secondary_cluster_identifier}-${count.index}"
  cluster_identifier = aws_rds_cluster.secondary.id

  instance_class = var.instance_class
  engine         = aws_rds_cluster.secondary.engine
  engine_version = aws_rds_cluster.secondary.engine_version

  publicly_accessible        = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  performance_insights_enabled = var.enable_performance_insights

  tags = merge(
    local.default_tags,
    {
      Name = "${local.secondary_cluster_identifier}-${count.index}"
    }
  )

  depends_on = [aws_rds_cluster.secondary]
}