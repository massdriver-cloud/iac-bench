locals {
  cluster_parameters = {
    "rds.force_ssl"              = "1"
    "rds.global_db_rpo"          = "20"
    "password_encryption"        = "scram-sha-256"
    "log_connections"            = "1"
    "log_disconnections"         = "1"
    "log_statement"              = "none"
    "log_min_duration_statement" = "-1"
  }
  primary_azs   = sort(distinct([for s in data.aws_subnet.primary : s.availability_zone]))
  secondary_azs = sort(distinct([for s in data.aws_subnet.secondary : s.availability_zone]))
}

resource "random_id" "snapshot" { byte_length = 4 }

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = true
  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "Disaster recovery requires two distinct regions."
    }
  }
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.name}-primary-"
  family      = "aurora-postgresql16"
  description = "TLS, replication RPO guardrail and safe connection logging"
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
  name_prefix = "${local.name}-secondary-"
  family      = "aurora-postgresql16"
  description = "Same promotion-ready parameters as primary"
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
  name              = "/aws/rds/cluster/${local.name}-primary/postgresql"
  retention_in_days = 365
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.name}-secondary/postgresql"
  retention_in_days = 365
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.name}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  engine_mode                         = "provisioned"
  master_username                     = "platform_admin"
  master_password                     = random_password.admin.result
  port                                = 5432
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  preferred_backup_window             = "07:00-08:00"
  preferred_maintenance_window        = "sun:09:00-sun:10:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.name}-primary-final-${random_id.snapshot.hex}"
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  depends_on                          = [aws_cloudwatch_log_group.primary, aws_secretsmanager_secret_version.admin]
  lifecycle { prevent_destroy = true }
}

resource "aws_rds_cluster_instance" "primary" {
  count                                 = 2
  identifier                            = "${local.name}-primary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  availability_zone                     = local.primary_azs[count.index]
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  publicly_accessible                   = false
  promotion_tier                        = count.index
  auto_minor_version_upgrade            = false
  apply_immediately                     = false
  preferred_maintenance_window          = count.index == 0 ? "sun:10:00-sun:11:00" : "sun:11:00-sun:12:00"
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
  lifecycle { prevent_destroy = true }
}

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.name}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  engine_mode                         = "provisioned"
  source_region                       = var.primary_region
  port                                = 5432
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  preferred_backup_window             = "08:00-09:00"
  preferred_maintenance_window        = "sun:09:00-sun:10:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.name}-secondary-final-${random_id.snapshot.hex}"
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  # Aurora requires the primary writer to exist before adding a secondary region.
  depends_on = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]
  lifecycle { prevent_destroy = true }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                              = aws.secondary
  count                                 = 2
  identifier                            = "${local.name}-secondary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  availability_zone                     = local.secondary_azs[count.index]
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  publicly_accessible                   = false
  promotion_tier                        = count.index
  auto_minor_version_upgrade            = false
  apply_immediately                     = false
  preferred_maintenance_window          = count.index == 0 ? "sun:10:00-sun:11:00" : "sun:11:00-sun:12:00"
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
  lifecycle { prevent_destroy = true }
}
