resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.cluster_identifier}-pg"
  family      = var.parameter_group_family
  description = "Secure Aurora PostgreSQL parameters for ${local.cluster_identifier}"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "pending-reboot"
  }
  tags = var.tags
}
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.cluster_identifier}-dr-pg"
  family      = var.parameter_group_family
  description = "Secure Aurora PostgreSQL parameters for ${local.cluster_identifier} DR"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "pending-reboot"
  }
  tags = var.tags
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.cluster_identifier}-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier            = local.cluster_identifier
  global_cluster_identifier     = aws_rds_global_cluster.this.id
  engine                        = "aurora-postgresql"
  engine_version                = var.engine_version
  database_name                 = var.database_name
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = var.backup_retention_days
  preferred_backup_window             = var.backup_window
  preferred_maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.cluster_identifier}-final"
  delete_automated_backups            = false

  serverlessv2_scaling_configuration {
    min_capacity = var.serverless_min_capacity
    max_capacity = var.serverless_max_capacity
  }
  tags       = var.tags
  depends_on = [aws_cloudwatch_log_group.primary_postgresql]
}

resource "aws_rds_cluster_instance" "primary" {
  count                                 = var.instances_per_region
  identifier                            = "${local.cluster_identifier}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  instance_class                        = "db.serverless"
  engine                                = "aurora-postgresql"
  engine_version                        = var.engine_version
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = false
  promotion_tier                        = count.index
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  tags                                  = var.tags
  depends_on                            = [aws_iam_role_policy_attachment.rds_monitoring]
}

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.cluster_identifier}-dr"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = var.backup_retention_days
  preferred_backup_window             = var.backup_window
  preferred_maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  apply_immediately                   = false
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.cluster_identifier}-dr-final"
  delete_automated_backups            = false

  serverlessv2_scaling_configuration {
    min_capacity = var.serverless_min_capacity
    max_capacity = var.serverless_max_capacity
  }
  tags       = var.tags
  depends_on = [aws_cloudwatch_log_group.secondary_postgresql]
}

resource "aws_rds_cluster_instance" "secondary" {
  count                                 = var.instances_per_region
  provider                              = aws.secondary
  identifier                            = "${local.cluster_identifier}-dr-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  instance_class                        = "db.serverless"
  engine                                = "aurora-postgresql"
  engine_version                        = var.engine_version
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = false
  promotion_tier                        = count.index
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  tags                                  = var.tags
  depends_on                            = [aws_iam_role_policy_attachment.rds_monitoring]
}

data "aws_caller_identity" "primary" {}
data "aws_caller_identity" "secondary" {
  provider = aws.secondary
}

resource "aws_iam_role_policy" "iam_database_connect" {
  for_each = local.iam_db_role_bindings
  name     = "${local.cluster_identifier}-db-${each.value.username}"
  role     = each.value.role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "rds-db:connect"
      Resource = [
        "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.primary.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${each.value.username}",
        "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.secondary.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${each.value.username}"
      ]
    }]
  })
}
