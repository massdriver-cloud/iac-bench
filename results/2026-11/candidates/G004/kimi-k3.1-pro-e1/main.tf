locals {
  base_name        = "${var.name}-${var.environment}"
  database_name    = coalesce(var.database_name, replace(var.name, "-", "_"))
  parameter_family = "aurora-postgresql${split(".", var.engine_version)[0]}"
  vpc_name         = "apps-${var.environment}"

  common_tags = merge({
    Application        = var.name
    Environment        = var.environment
    ManagedBy          = "OpenTofu"
    Module             = "aurora-postgresql-global"
    DataClassification = "customer-payment"
  }, var.tags)
}

data "aws_caller_identity" "primary" {
  provider = aws.primary
}

data "aws_caller_identity" "secondary" {
  provider = aws.secondary
}

data "aws_partition" "primary" {
  provider = aws.primary
}

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = "${local.base_name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be different."
    }

    precondition {
      condition     = data.aws_caller_identity.primary.account_id == data.aws_caller_identity.secondary.account_id
      error_message = "Both regional providers must use the same AWS account so IAM authentication and monitoring can be managed centrally."
    }
  }
}

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name        = "${local.base_name}-primary-pg${split(".", var.engine_version)[0]}"
  family      = local.parameter_family
  description = "Security and global-RPO settings for ${local.base_name}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Aurora managed RPO throttles commits when every secondary is beyond this
  # lag. This deliberately trades some write availability for the stated RPO.
  parameter {
    name  = "rds.global_db_rpo"
    value = tostring(var.global_rpo_milliseconds)
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.base_name}-secondary-pg${split(".", var.engine_version)[0]}"
  family      = local.parameter_family
  description = "Security and global-RPO settings for ${local.base_name}"

  # Keep the same settings in DR so they remain effective after promotion.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "rds.global_db_rpo"
    value = tostring(var.global_rpo_milliseconds)
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier                  = "${local.base_name}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = local.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  port                                = var.port
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = "06:00-07:00"
  preferred_maintenance_window = "sun:07:00-sun:08:00"
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.base_name}-primary-final"
  allow_major_version_upgrade  = false
  apply_immediately            = false

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    precondition {
      condition     = var.iam_database_user_name != var.master_username
      error_message = "The IAM application role must be different from the master username."
    }
  }
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.instances_per_region

  identifier                      = "${local.base_name}-p-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.primary.id
  engine                          = aws_rds_global_cluster.this.engine
  engine_version                  = aws_rds_global_cluster.this.engine_version
  instance_class                  = var.instance_class
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  availability_zone               = try(local.primary_availability_zones[count.index % length(local.primary_availability_zones)], null)
  promotion_tier                  = count.index
  publicly_accessible             = false
  auto_minor_version_upgrade      = false
  apply_immediately               = false
  copy_tags_to_snapshot           = true
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary.arn
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.enhanced_monitoring.arn

  tags = {
    Name = "${local.base_name}-p-${count.index + 1}"
    Role = count.index == 0 ? "writer-preferred" : "reader"
  }
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier                  = "${local.base_name}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  port                                = var.port
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  preferred_maintenance_window = "sun:08:00-sun:09:00"
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.base_name}-secondary-final"
  allow_major_version_upgrade  = false
  apply_immediately            = false

  # The primary writer must exist before AWS can add a secondary global member.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.instances_per_region

  identifier                      = "${local.base_name}-s-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.secondary.id
  engine                          = aws_rds_global_cluster.this.engine
  engine_version                  = aws_rds_global_cluster.this.engine_version
  instance_class                  = var.instance_class
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  availability_zone               = try(local.secondary_availability_zones[count.index % length(local.secondary_availability_zones)], null)
  promotion_tier                  = count.index
  publicly_accessible             = false
  auto_minor_version_upgrade      = false
  apply_immediately               = false
  copy_tags_to_snapshot           = true
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary.arn
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.enhanced_monitoring.arn

  tags = {
    Name = "${local.base_name}-s-${count.index + 1}"
    Role = "disaster-recovery-reader"
  }
}
