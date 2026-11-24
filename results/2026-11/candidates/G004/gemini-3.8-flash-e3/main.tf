# Aurora Global Cluster
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${var.name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = local.engine_version
  deletion_protection       = var.deletion_protection
  storage_encrypted         = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name}-global"
    }
  )
}

# CloudWatch Log Groups for PostgreSQL Export Logs
resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${var.name}-primary/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.primary_kms_key_arn

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-primary-logs"
      Region = var.primary_region
    }
  )
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${var.name}-secondary/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.secondary_kms_key_arn

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-secondary-logs"
      Region = var.secondary_region
    }
  )
}

# Primary Aurora PostgreSQL Cluster
resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${var.name}-primary"
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  database_name                       = local.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = local.primary_kms_key_arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  kms_key_id                          = local.primary_kms_key_arn
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = var.skip_final_snapshot
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-primary"
      Region = var.primary_region
    }
  )

  depends_on = [
    aws_cloudwatch_log_group.primary
  ]
}

# Secondary Aurora PostgreSQL Cluster (Cross-Region DR)
resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier                  = "${var.name}-secondary"
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  kms_key_id                          = local.secondary_kms_key_arn
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = var.skip_final_snapshot
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-secondary"
      Region = var.secondary_region
    }
  )

  depends_on = [
    aws_rds_cluster.primary,
    aws_cloudwatch_log_group.secondary
  ]
}

# Primary Region Cluster Instances
resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier                            = "${var.name}-primary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  instance_class                        = var.instance_class
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = aws_rds_cluster.primary.engine_version
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  db_parameter_group_name               = aws_db_parameter_group.primary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? local.primary_kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  copy_tags_to_snapshot                 = true

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-primary-${count.index + 1}"
      Region = var.primary_region
      Role   = count.index == 0 ? "writer" : "reader"
    }
  )
}

# Secondary Region Cluster Instances
resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier                            = "${var.name}-secondary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  instance_class                        = var.instance_class
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = aws_rds_cluster.secondary.engine_version
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  db_parameter_group_name               = aws_db_parameter_group.secondary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? local.secondary_kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  copy_tags_to_snapshot                 = true

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-secondary-${count.index + 1}"
      Region = var.secondary_region
      Role   = "reader"
    }
  )
}
