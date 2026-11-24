locals {
  id   = "${var.name}-${var.environment}"
  tags = merge(var.tags, { Environment = var.environment, Service = var.name, ManagedBy = "OpenTofu" })
}
resource "aws_kms_key" "primary" {
  description             = "Aurora ${local.id} primary encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}
resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora ${local.id} secondary encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}
resource "random_password" "master" {
  length  = 40
  special = false
}
resource "random_id" "snapshot" {
  byte_length = 4
}
resource "aws_secretsmanager_secret" "master" {
  name                    = "${local.id}/aurora-master"
  description             = "Bootstrap administrator credentials for ${local.id}; prefer IAM authentication for applications"
  recovery_window_in_days = 30
  replica {
    region = var.secondary_region
  }
  tags = local.tags
}
resource "aws_secretsmanager_secret_version" "master" {
  secret_id     = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({ username = "dbadmin", password = random_password.master.result })
}
resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.id}-aurora-pg16-primary"
  family      = "aurora-postgresql16"
  description = "Require TLS for ${local.id}"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  tags = local.tags
}
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.id}-aurora-pg16-secondary"
  family      = "aurora-postgresql16"
  description = "Require TLS for ${local.id}"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  tags = local.tags
}
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = true
}
resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.id}-primary/postgresql"
  retention_in_days = 90
  tags              = local.tags
}
resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.id}-secondary/postgresql"
  retention_in_days = 90
  tags              = local.tags
}
resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.id}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  database_name                       = var.database_name
  master_username                     = "dbadmin"
  master_password                     = random_password.master.result
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  preferred_backup_window             = "03:00-04:00"
  preferred_maintenance_window        = "sun:05:00-sun:06:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.id}-primary-final-${random_id.snapshot.hex}"
  copy_tags_to_snapshot               = true
  tags                                = local.tags
  depends_on                          = [aws_cloudwatch_log_group.primary, aws_secretsmanager_secret_version.master]
}
resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.id}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  preferred_backup_window             = "04:00-05:00"
  preferred_maintenance_window        = "sun:06:00-sun:07:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.id}-secondary-final-${random_id.snapshot.hex}"
  copy_tags_to_snapshot               = true
  tags                                = local.tags
  depends_on                          = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]
}
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider            = aws.secondary
  alarm_name          = "${local.id}-global-replication-lag"
  alarm_description   = "Global replication lag exceeds two seconds or stops reporting; investigate RPO exposure."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 2000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = var.secondary_alarm_actions
  tags                = local.tags
}
