################################################################################
# Primary Region Aurora Cluster & Multi-AZ Instances
################################################################################

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = local.primary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  database_name             = aws_rds_global_cluster.this.database_name
  port                      = var.port

  # Master credentials managed and rotated by AWS Secrets Manager (no plaintext in state)
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  storage_type                        = var.storage_type == "aurora-iopt1" ? "aurora-iopt1" : null
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.skip_final_snapshot ? null : "${local.primary_cluster_id}-final"
  apply_immediately           = var.apply_immediately
  allow_major_version_upgrade = false

  enabled_cloudwatch_logs_exports = local.cloudwatch_log_exports

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.primary_is_serverless ? [1] : []
    content {
      min_capacity = var.serverlessv2_min_capacity
      max_capacity = var.serverlessv2_max_capacity
    }
  }

  tags = {
    Name = local.primary_cluster_id
    role = "primary"
  }

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.primary_instance_count

  identifier              = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.primary.id
  instance_class          = var.instance_class
  engine                  = aws_rds_cluster.primary.engine
  engine_version          = aws_rds_cluster.primary.engine_version
  db_subnet_group_name    = aws_db_subnet_group.primary.name
  db_parameter_group_name = aws_db_parameter_group.primary.name

  # Spread instances deterministically across distinct AZs in the database subnet group
  availability_zone = local.primary_azs[count.index % length(local.primary_azs)]
  promotion_tier    = count.index == 0 ? 0 : (count.index == 1 ? 1 : 2)

  publicly_accessible        = false
  ca_cert_identifier         = local.ca_cert_identifier
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = {
    Name = "${local.primary_cluster_id}-${count.index + 1}"
    role = count.index == 0 ? "primary-writer" : "primary-reader"
  }
}

################################################################################
# Secondary Region Aurora Cluster & Warm Standby Instances (Sub-Minute RTO)
################################################################################

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  port                      = var.port

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  storage_type                        = var.storage_type == "aurora-iopt1" ? "aurora-iopt1" : null
  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.enable_global_write_forwarding

  # Pre-configured backup & maintenance windows so promotion immediately inherits prod policy
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection = var.deletion_protection
  # AWS RDS forbids creating a final snapshot on a secondary global cluster member
  skip_final_snapshot         = true
  apply_immediately           = var.apply_immediately
  allow_major_version_upgrade = false

  enabled_cloudwatch_logs_exports = local.cloudwatch_log_exports

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.secondary_is_serverless ? [1] : []
    content {
      min_capacity = var.serverlessv2_min_capacity
      max_capacity = var.serverlessv2_max_capacity
    }
  }

  tags = {
    Name = local.secondary_cluster_id
    role = "secondary"
  }

  # Primary cluster MUST have at least one DB instance before attaching a secondary region
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary
  ]

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier              = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.secondary.id
  instance_class          = local.secondary_instance_class
  engine                  = aws_rds_cluster.secondary.engine
  engine_version          = aws_rds_cluster.secondary.engine_version
  db_subnet_group_name    = aws_db_subnet_group.secondary.name
  db_parameter_group_name = aws_db_parameter_group.secondary.name

  # Warm standby instances spread across distinct AZs for immediate post-failover Multi-AZ HA
  availability_zone = local.secondary_azs[count.index % length(local.secondary_azs)]
  promotion_tier    = count.index == 0 ? 0 : 1

  publicly_accessible        = false
  ca_cert_identifier         = local.ca_cert_identifier
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = {
    Name = "${local.secondary_cluster_id}-${count.index + 1}"
    role = "secondary-standby"
  }
}
