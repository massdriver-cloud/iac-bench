# -----------------------------------------------------------------------------
# Primary (writable) cluster, in the primary region.
#
# Master credentials are generated and managed by RDS inside Secrets Manager
# (encrypted with the cluster's KMS key) - no password is ever stored in
# OpenTofu state. Applications connect with IAM auth tokens instead.
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier = "${local.name}-${var.primary_region}"
  engine             = local.engine
  engine_version     = local.engine_version

  global_cluster_identifier = aws_rds_global_cluster.this.id

  database_name                 = var.database_name
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  port                            = var.port

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  iam_database_authentication_enabled = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  backup_retention_period = local.backup_retention_period
  copy_tags_to_snapshot   = true

  deletion_protection       = local.deletion_protection
  skip_final_snapshot       = local.skip_final_snapshot
  final_snapshot_identifier = "${local.name}-${var.primary_region}-final"

  preferred_maintenance_window = var.preferred_maintenance_window

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [true] : []
    content {
      min_capacity = var.serverless_v2_min_capacity
      max_capacity = var.serverless_v2_max_capacity
    }
  }

  tags = {
    Name = "${local.name}-${var.primary_region}"
  }
}

# -----------------------------------------------------------------------------
# Secondary (readable standby) cluster, in the failover region.
#
# Created as a member of the global database: storage replication, engine
# settings, the initial database, the master credentials and the cluster
# parameter group are all inherited from the primary cluster, so none of those
# are set here. It serves local reads (low latency for read-heavy traffic in
# the second region) and is the promotion target during a regional failover.
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  # The primary cluster (and its writer instance) must exist and be healthy
  # before the secondary can be attached to the global database.
  depends_on = [
    aws_rds_cluster.primary,
    aws_rds_cluster_instance.primary
  ]

  cluster_identifier = "${local.name}-${var.secondary_region}"
  engine             = local.engine
  engine_version     = local.engine_version

  global_cluster_identifier = aws_rds_global_cluster.this.id
  source_region             = var.primary_region

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.secondary.id]
  port                   = var.port

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  iam_database_authentication_enabled = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  backup_retention_period = var.secondary_backup_retention_period
  copy_tags_to_snapshot   = true

  deletion_protection       = local.deletion_protection
  skip_final_snapshot       = local.skip_final_snapshot
  final_snapshot_identifier = "${local.name}-${var.secondary_region}-final"

  preferred_maintenance_window = var.preferred_maintenance_window

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [true] : []
    content {
      min_capacity = var.serverless_v2_min_capacity
      max_capacity = var.serverless_v2_max_capacity
    }
  }

  tags = {
    Name = "${local.name}-${var.secondary_region}"
  }
}
