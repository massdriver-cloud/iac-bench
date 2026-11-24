# TLS everywhere: the cluster parameter group refuses plaintext connections.
# Connection and disconnection logging give a baseline audit trail for a
# database holding customer and payment data.
resource "aws_rds_cluster_parameter_group" "primary" {
  name        = local.prefix
  family      = local.parameter_group_family
  description = "Production defaults for ${local.prefix}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name = local.prefix
  }
}

# The read-write cluster during normal operation.
resource "aws_rds_cluster" "primary" {
  cluster_identifier        = local.primary_cluster_identifier
  engine                    = local.engine
  engine_version            = var.engine_version
  engine_mode               = "provisioned"
  global_cluster_identifier = aws_rds_global_cluster.this.id

  database_name   = local.database_name
  master_username = var.master_username
  master_password = random_password.master.result

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection = var.deletion_protection
  skip_final_snapshot = false

  enabled_cloudwatch_logs_exports     = ["postgresql"]
  iam_database_authentication_enabled = true
}

# Writer plus readers, placed in distinct AZs by Aurora: a single instance or
# AZ failure fails over within the region in well under a minute.
resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier         = "${local.prefix}-${count.index}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = local.engine
  engine_version     = var.engine_version
  instance_class     = var.instance_class
  promotion_tier     = count.index

  auto_minor_version_upgrade = true
  publicly_accessible        = false

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
}
