# Same hardened posture as the primary region.
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

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

# The warm standby. It is read-only (but serves local reads in the secondary
# region) until a regional failover promotes it to read-write. It inherits the
# database name and master credentials from the primary via the global cluster,
# so they are not declared here.
resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_identifier
  engine                    = local.engine
  engine_version            = var.engine_version
  engine_mode               = "provisioned"
  global_cluster_identifier = aws_rds_global_cluster.this.id

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection = var.deletion_protection
  skip_final_snapshot = false

  enabled_cloudwatch_logs_exports     = ["postgresql"]
  iam_database_authentication_enabled = true

  # The primary cluster must exist before a secondary can join the global
  # database.
  depends_on = [aws_rds_cluster.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  count = var.secondary_instance_count

  provider = aws.secondary

  identifier         = "${local.prefix}-dr-${count.index}"
  cluster_identifier = aws_rds_cluster.secondary.id
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
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
}
