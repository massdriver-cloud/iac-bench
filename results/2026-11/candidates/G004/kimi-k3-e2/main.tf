# Architecture: one Aurora global database with a writer cluster in the
# primary region and a replicated cluster in the secondary region. Aurora
# replicates storage with sub-second typical lag (RPO of seconds), and a
# managed switchover promotes the secondary in about a minute with zero data
# loss (RTO of minutes).

check "regions_differ" {
  assert {
    condition     = var.primary_region != var.secondary_region
    error_message = "primary_region and secondary_region must be two different AWS regions."
  }
}

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = local.global_cluster_id
  engine                    = local.engine
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

# Pre-create the CloudWatch log groups that PostgreSQL logs are exported to,
# so retention is under the module's control from day one.
resource "aws_cloudwatch_log_group" "primary_postgresql" {
  provider          = aws.primary
  name              = "/aws/rds/cluster/${local.primary_cluster_id}/postgresql"
  retention_in_days = var.cloudwatch_log_retention_in_days
}

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/postgresql"
  retention_in_days = var.cloudwatch_log_retention_in_days
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = local.primary_cluster_id
  engine                    = local.engine
  engine_version            = var.engine_version
  global_cluster_identifier = aws_rds_global_cluster.this.id

  database_name   = local.database_name
  master_username = var.master_username
  port            = var.port

  # Break-glass master credentials: generated and rotated by RDS in Secrets
  # Manager (encrypted with the regional CMK) unless the caller supplies a
  # password explicitly. Applications authenticate with IAM instead.
  master_password               = var.master_password
  manage_master_user_password   = var.master_password == null ? true : null
  master_user_secret_kms_key_id = var.master_password == null ? aws_kms_key.primary.arn : null

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  apply_immediately         = var.apply_immediately
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.primary_cluster_id}-final"

  depends_on = [aws_cloudwatch_log_group.primary_postgresql]
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.primary_instance_count

  identifier         = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = local.engine
  engine_version     = var.engine_version

  publicly_accessible        = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  # Writer stays at tier 0, readers at tier 1 for predictable in-region
  # failover ordering.
  promotion_tier = count.index == 0 ? 0 : 1

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring.arn : null

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_period
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_id
  engine                    = local.engine
  engine_version            = var.engine_version
  global_cluster_identifier = aws_rds_global_cluster.this.id

  # Credentials, database name and port are inherited from the global cluster.

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.secondary.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.global_write_forwarding ? true : null
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  apply_immediately         = var.apply_immediately
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.secondary_cluster_id}-final"

  # The primary cluster must exist and hold at least one instance before a
  # secondary region can join the global database.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary_postgresql,
  ]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = var.instance_class
  engine             = local.engine
  engine_version     = var.engine_version

  publicly_accessible        = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true
  promotion_tier             = 1

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring.arn : null

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_period
}
