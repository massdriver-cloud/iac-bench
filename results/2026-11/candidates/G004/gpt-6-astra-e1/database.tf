locals {
  cluster_parameters = {
    "rds.force_ssl"              = "1"
    "password_encryption"        = "scram-sha-256"
    "log_connections"            = "1"
    "log_disconnections"         = "1"
    "log_statement"              = "none"
    "log_min_duration_statement" = "-1"
    "log_min_error_statement"    = "panic"
  }
}
resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.prefix}-pg16-"
  family      = "aurora-postgresql16"
  description = "TLS required; connection auditing without SQL statement or payment payload logging"
  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.prefix}-pg16-"
  family      = "aurora-postgresql16"
  description = "Same hardened PostgreSQL settings on the disaster-recovery cluster"
  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.prefix}-primary/postgresql"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.primary.arn
}
resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.prefix}-secondary/postgresql"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.secondary.arn
}

resource "aws_rds_global_cluster" "database" {
  global_cluster_identifier = local.prefix
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = true
  lifecycle { prevent_destroy = true }
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.prefix}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.database.id
  engine                              = "aurora-postgresql"
  engine_mode                         = "provisioned"
  engine_version                      = var.engine_version
  database_name                       = var.database_name
  master_username                     = "dbadmin"
  master_password                     = random_password.administrator.result
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  port                                = 5432
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  preferred_backup_window             = "06:00-07:00"
  preferred_maintenance_window        = "sun:08:00-sun:09:00"
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.prefix}-primary-final-${random_id.snapshot.hex}"
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  depends_on                          = [aws_cloudwatch_log_group.primary, aws_secretsmanager_secret_version.administrator]
  lifecycle {
    prevent_destroy = true
    # AWS manages replication direction after a managed global failover or switchover.
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster" "secondary" {
  provider                  = aws.secondary
  cluster_identifier        = "${local.prefix}-secondary"
  global_cluster_identifier = aws_rds_global_cluster.database.id
  engine                    = "aurora-postgresql"
  engine_mode               = "provisioned"
  engine_version            = var.engine_version
  # A global secondary receives users, credentials, schema and data from its writer.
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  port                                = 5432
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  preferred_backup_window             = "07:00-08:00"
  preferred_maintenance_window        = "sun:09:00-sun:10:00"
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.prefix}-secondary-final-${random_id.snapshot.hex}"
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  depends_on                          = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count                                 = var.instances_per_region
  identifier                            = "${local.prefix}-primary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = "aurora-postgresql"
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  availability_zone                     = element(local.primary_azs, count.index)
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = false
  apply_immediately                     = false
  promotion_tier                        = count.index
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true
  preferred_maintenance_window          = "sun:08:00-sun:09:00"
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
}
resource "aws_rds_cluster_instance" "secondary" {
  provider                              = aws.secondary
  count                                 = var.instances_per_region
  identifier                            = "${local.prefix}-secondary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = "aurora-postgresql"
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  availability_zone                     = element(local.secondary_azs, count.index)
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = false
  apply_immediately                     = false
  promotion_tier                        = count.index
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true
  preferred_maintenance_window          = "sun:09:00-sun:10:00"
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
}
