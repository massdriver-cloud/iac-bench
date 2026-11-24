############################################
# Aurora Global Database
#
# Primary region: writer + readers.  Secondary region: a full copy kept in sync by
# Aurora storage-level replication (typically < 1s lag). On a regional failure the
# secondary is promoted with managed failover (RTO minutes, RPO seconds). Both
# regions are built identically so nothing has to change after a promotion.
############################################

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = "${local.name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    # Major/minor version upgrades of a global cluster are done out-of-band (console/CLI)
    # and would otherwise show as perpetual drift against the member clusters.
    ignore_changes = [engine_version]
  }
}

############################################
# Primary regional cluster
############################################

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = local.primary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  engine_mode               = "provisioned"
  database_name             = local.database_name
  port                      = 5432

  # Credentials: master password generated & rotated by Secrets Manager (never in state);
  # applications use IAM authentication.
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true

  # Encryption at rest with a customer-managed key.
  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  # Networking.
  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  # Backups and protection.
  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.primary_cluster_id}-final"
  apply_immediately            = var.apply_immediately

  # Observability.
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = local.primary_cluster_id }

  lifecycle {
    ignore_changes = [
      engine_version,
      # After a managed failover AWS rewrites this on both clusters.
      replication_source_identifier,
    ]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.instances_per_region

  identifier         = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  instance_class     = var.instance_class

  # Lower tier => preferred as the failover target within the region.
  promotion_tier = count.index

  db_subnet_group_name    = aws_db_subnet_group.primary.name
  db_parameter_group_name = aws_db_parameter_group.primary.name
  publicly_accessible     = false
  ca_cert_identifier      = "rds-ca-rsa2048-g1"

  auto_minor_version_upgrade   = true
  preferred_maintenance_window = var.preferred_maintenance_window
  apply_immediately            = var.apply_immediately
  copy_tags_to_snapshot        = true

  monitoring_interval = var.monitoring_interval_seconds
  monitoring_role_arn = aws_iam_role.monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  tags = { Name = "${local.primary_cluster_id}-${count.index + 1}" }

  lifecycle {
    ignore_changes = [engine_version]
  }

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}

############################################
# Secondary regional cluster
############################################

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  engine_mode               = "provisioned"
  port                      = 5432

  # Secondary clusters inherit credentials from the global cluster; IAM auth must be set per cluster.
  iam_database_authentication_enabled = true

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.secondary.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.secondary_cluster_id}-final"
  apply_immediately            = var.apply_immediately

  enable_global_write_forwarding = var.enable_global_write_forwarding

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = local.secondary_cluster_id }

  lifecycle {
    ignore_changes = [
      engine_version,
      replication_source_identifier,
    ]
  }

  # A secondary can only be added once the primary has a running writer.
  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.instances_per_region

  identifier         = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class
  promotion_tier     = count.index

  db_subnet_group_name    = aws_db_subnet_group.secondary.name
  db_parameter_group_name = aws_db_parameter_group.secondary.name
  publicly_accessible     = false
  ca_cert_identifier      = "rds-ca-rsa2048-g1"

  auto_minor_version_upgrade   = true
  preferred_maintenance_window = var.preferred_maintenance_window
  apply_immediately            = var.apply_immediately
  copy_tags_to_snapshot        = true

  monitoring_interval = var.monitoring_interval_seconds
  monitoring_role_arn = aws_iam_role.monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  tags = { Name = "${local.secondary_cluster_id}-${count.index + 1}" }

  lifecycle {
    ignore_changes = [engine_version]
  }

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}
