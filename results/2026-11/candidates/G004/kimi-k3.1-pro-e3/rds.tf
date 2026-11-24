resource "aws_cloudwatch_log_group" "primary_postgresql" {
  name              = "/aws/rds/cluster/${local.primary_cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = {
    Name = "${local.primary_cluster_identifier}-postgresql"
  }
}

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.secondary_cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = {
    Name = "${local.secondary_cluster_identifier}-postgresql"
  }
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${var.name}-aurora-postgresql"
  family      = "aurora-postgresql${split(".", var.engine_version)[0]}"
  description = "TLS and audit/logging baseline for ${var.name} Aurora PostgreSQL"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "immediate"
    }
  }

  tags = {
    Name = "${var.name}-aurora-postgresql"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${var.name}-aurora-postgresql"
  family      = "aurora-postgresql${split(".", var.engine_version)[0]}"
  description = "TLS and audit/logging baseline for ${var.name} Aurora PostgreSQL disaster recovery"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "immediate"
    }
  }

  tags = {
    Name = "${var.name}-aurora-postgresql"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${var.name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "Aurora Global Database requires different primary and secondary Regions."
    }

    precondition {
      condition     = data.aws_caller_identity.primary.account_id == data.aws_caller_identity.secondary.account_id
      error_message = "Both provider configurations must target the same AWS account. Use separate global clusters for separate accounts."
    }
  }
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = local.primary_cluster_identifier
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = var.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  port                                = var.database_port
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  allow_major_version_upgrade = false
  apply_immediately           = false
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = "${var.name}-primary-final"

  depends_on = [aws_cloudwatch_log_group.primary_postgresql]
}

resource "aws_rds_cluster_instance" "primary" {
  for_each = { for index in range(var.primary_instance_count) : tostring(index) => index }

  identifier           = "${local.primary_cluster_identifier}-${each.key}"
  cluster_identifier   = aws_rds_cluster.primary.id
  engine               = aws_rds_global_cluster.this.engine
  engine_version       = aws_rds_global_cluster.this.engine_version
  instance_class       = var.instance_class
  db_subnet_group_name = aws_db_subnet_group.primary.name
  promotion_tier       = each.value

  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7

  depends_on = [
    aws_iam_role_policy_attachment.enhanced_monitoring,
    aws_rds_cluster_parameter_group.primary,
  ]

  tags = {
    Name = "${local.primary_cluster_identifier}-${each.key}"
    Role = each.key == 0 ? "writer-preferred" : "reader"
  }
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier                  = local.secondary_cluster_identifier
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  port                                = var.database_port
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  allow_major_version_upgrade = false
  apply_immediately           = false
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = "${var.name}-secondary-final"

  # A secondary cluster can only be attached after the primary has at least one
  # running instance. This also gives deterministic creation and destruction.
  depends_on = [
    aws_cloudwatch_log_group.secondary_postgresql,
    aws_rds_cluster_instance.primary,
  ]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  for_each = { for index in range(var.secondary_instance_count) : tostring(index) => index }

  identifier           = "${local.secondary_cluster_identifier}-${each.key}"
  cluster_identifier   = aws_rds_cluster.secondary.id
  engine               = aws_rds_global_cluster.this.engine
  engine_version       = aws_rds_global_cluster.this.engine_version
  instance_class       = var.instance_class
  db_subnet_group_name = aws_db_subnet_group.secondary.name
  promotion_tier       = each.value

  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7

  depends_on = [
    aws_iam_role_policy_attachment.enhanced_monitoring,
    aws_rds_cluster_parameter_group.secondary,
  ]

  tags = {
    Name = "${local.secondary_cluster_identifier}-${each.key}"
    Role = "disaster-recovery-reader"
  }
}
