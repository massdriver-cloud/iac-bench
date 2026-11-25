############################################
# Cluster parameter groups (regional resources, identical content)
############################################

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = local.name
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL ${local.name}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = local.name
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL ${local.name}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

############################################
# CloudWatch log groups (pre-created so retention is controlled)
############################################

resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.name}-${var.primary_region}/postgresql"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.name}-${var.secondary_region}/postgresql"
  retention_in_days = var.log_retention_days
}

############################################
# Global database
############################################

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = local.engine
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

############################################
# Primary cluster
############################################

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = "${local.name}-${var.primary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  engine_mode               = "provisioned"
  storage_type              = var.storage_type
  port                      = var.port

  database_name                 = local.database_name
  master_username               = var.master_username
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
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-${var.primary_region}-final"
  apply_immediately         = var.apply_immediately

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    # After a managed failover/switchover the roles of the two clusters swap
    # and AWS rewrites this attribute; don't fight it.
    ignore_changes = [replication_source_identifier, global_cluster_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier         = "${local.name}-${var.primary_region}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.primary.name
  publicly_accessible  = false
  promotion_tier       = count.index

  # Version changes are driven through var.engine_version so both regions
  # move together; AWS-initiated minor upgrades would make them drift.
  auto_minor_version_upgrade   = false
  preferred_maintenance_window = var.preferred_maintenance_window
  apply_immediately            = var.apply_immediately

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  copy_tags_to_snapshot = true
}

############################################
# Secondary cluster (disaster recovery)
############################################

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.name}-${var.secondary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  engine_mode               = "provisioned"
  storage_type              = var.storage_type
  port                      = var.port

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  enable_global_write_forwarding      = var.enable_global_write_forwarding

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-${var.secondary_region}-final"
  apply_immediately         = var.apply_immediately

  # A secondary can only be attached once the primary has a writer instance.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  lifecycle {
    ignore_changes = [replication_source_identifier, global_cluster_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.name}-${var.secondary_region}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.secondary.name
  publicly_accessible  = false
  promotion_tier       = count.index

  auto_minor_version_upgrade   = false
  preferred_maintenance_window = var.preferred_maintenance_window
  apply_immediately            = var.apply_immediately

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  copy_tags_to_snapshot = true
}
