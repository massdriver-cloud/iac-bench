locals {
  family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  primary_subnet_ids   = var.primary_subnet_ids != null ? var.primary_subnet_ids : data.aws_subnets.primary[0].ids
  secondary_subnet_ids = var.secondary_subnet_ids != null ? var.secondary_subnet_ids : data.aws_subnets.secondary[0].ids

  primary_kms_key_arn   = var.kms_key_arn_primary != null ? var.kms_key_arn_primary : aws_kms_key.primary[0].arn
  secondary_kms_key_arn = var.kms_key_arn_secondary != null ? var.kms_key_arn_secondary : aws_kms_key.secondary[0].arn
}

# Data Sources for Subnet Discovery
data "aws_subnets" "primary" {
  count = var.primary_subnet_ids == null ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.primary_vpc_id]
  }
  filter {
    name   = "tag:${var.subnet_tier_tag_key}"
    values = [var.subnet_tier_tag_value]
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary
  count    = var.secondary_subnet_ids == null ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.secondary_vpc_id]
  }
  filter {
    name   = "tag:${var.subnet_tier_tag_key}"
    values = [var.subnet_tier_tag_value]
  }
}

data "aws_vpc" "primary" {
  count = var.allow_vpc_cidr_ingress ? 1 : 0
  id    = var.primary_vpc_id
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  count    = var.allow_vpc_cidr_ingress ? 1 : 0
  id       = var.secondary_vpc_id
}

# KMS Keys for Storage Encryption
resource "aws_kms_key" "primary" {
  count                   = var.kms_key_arn_primary == null ? 1 : 0
  description             = "KMS CMK for ${var.name} Aurora PostgreSQL primary cluster (${var.environment})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.name}-${var.environment}-primary-kms" })
}

resource "aws_kms_alias" "primary" {
  count         = var.kms_key_arn_primary == null ? 1 : 0
  name          = "alias/${var.name}-${var.environment}-aurora-primary"
  target_key_id = aws_kms_key.primary[0].key_id
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  count                   = var.kms_key_arn_secondary == null ? 1 : 0
  description             = "KMS CMK for ${var.name} Aurora PostgreSQL secondary cluster (${var.environment})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.name}-${var.environment}-secondary-kms" })
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  count         = var.kms_key_arn_secondary == null ? 1 : 0
  name          = "alias/${var.name}-${var.environment}-aurora-secondary"
  target_key_id = aws_kms_key.secondary[0].key_id
}

# DB Subnet Groups
resource "aws_db_subnet_group" "primary" {
  name        = "${var.name}-${var.environment}-primary-subnet-group"
  description = "Database subnet group for ${var.name} primary cluster in ${var.environment}"
  subnet_ids  = local.primary_subnet_ids
  tags        = merge(var.tags, { Name = "${var.name}-${var.environment}-primary-subnet-group" })
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-${var.environment}-secondary-subnet-group"
  description = "Database subnet group for ${var.name} secondary cluster in ${var.environment}"
  subnet_ids  = local.secondary_subnet_ids
  tags        = merge(var.tags, { Name = "${var.name}-${var.environment}-secondary-subnet-group" })
}

# Security Groups
resource "aws_security_group" "primary" {
  name        = "${var.name}-${var.environment}-primary-sg"
  description = "Security group for ${var.name} Aurora primary cluster"
  vpc_id      = var.primary_vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-${var.environment}-primary-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "primary_vpc_ingress" {
  count             = var.allow_vpc_cidr_ingress ? 1 : 0
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = data.aws_vpc.primary[0].cidr_block
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg_ingress" {
  for_each                     = toset(var.allowed_security_group_ids_primary)
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr_ingress" {
  for_each          = toset(var.allowed_cidr_blocks_primary)
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = each.value
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-${var.environment}-secondary-sg"
  description = "Security group for ${var.name} Aurora secondary cluster"
  vpc_id      = var.secondary_vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-${var.environment}-secondary-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "secondary_vpc_ingress" {
  provider          = aws.secondary
  count             = var.allow_vpc_cidr_ingress ? 1 : 0
  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = data.aws_vpc.secondary[0].cidr_block
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg_ingress" {
  provider                     = aws.secondary
  for_each                     = toset(var.allowed_security_group_ids_secondary)
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr_ingress" {
  provider          = aws.secondary
  for_each          = toset(var.allowed_cidr_blocks_secondary)
  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = each.value
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
}

# Parameter Groups
resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${var.name}-${var.environment}-primary-cluster-pg"
  family      = local.family
  description = "Cluster parameter group for ${var.name} primary cluster"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  dynamic "parameter" {
    for_each = var.custom_cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-primary-cluster-pg" })
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-${var.environment}-secondary-cluster-pg"
  family      = local.family
  description = "Cluster parameter group for ${var.name} secondary cluster"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  dynamic "parameter" {
    for_each = var.custom_cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-secondary-cluster-pg" })
}

resource "aws_db_parameter_group" "primary" {
  name        = "${var.name}-${var.environment}-primary-db-pg"
  family      = local.family
  description = "DB parameter group for ${var.name} primary instances"

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

  dynamic "parameter" {
    for_each = var.custom_db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-primary-db-pg" })
}

resource "aws_db_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-${var.environment}-secondary-db-pg"
  family      = local.family
  description = "DB parameter group for ${var.name} secondary instances"

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

  dynamic "parameter" {
    for_each = var.custom_db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-secondary-db-pg" })
}

# IAM Roles for Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring_primary" {
  name = "${var.name}-${var.environment}-primary-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-primary-rds-monitoring" })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_primary" {
  role       = aws_iam_role.rds_monitoring_primary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_iam_role" "rds_monitoring_secondary" {
  provider = aws.secondary
  name     = "${var.name}-${var.environment}-sec-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-sec-rds-monitoring" })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_secondary" {
  provider   = aws.secondary
  role       = aws_iam_role.rds_monitoring_secondary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Global Database Cluster
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${var.name}-${var.environment}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

# Primary Aurora Cluster
resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${var.name}-${var.environment}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = var.database_name
  master_username                     = var.master_username
  master_password                     = var.master_password
  manage_master_user_password         = var.master_password == null ? var.manage_master_user_password : null
  port                                = var.port
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  kms_key_id                          = local.primary_kms_key_arn
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${var.name}-${var.environment}-primary-final"
  copy_tags_to_snapshot               = true
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-primary-cluster" })
}

resource "aws_rds_cluster_instance" "primary" {
  count                           = var.primary_instance_count
  identifier                      = "${var.name}-${var.environment}-primary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.primary.id
  engine                          = aws_rds_cluster.primary.engine
  engine_version                  = aws_rds_cluster.primary.engine_version
  instance_class                  = var.instance_class
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  db_parameter_group_name         = aws_db_parameter_group.primary.name
  publicly_accessible             = false
  auto_minor_version_upgrade      = var.auto_minor_version_upgrade
  preferred_maintenance_window    = var.preferred_maintenance_window
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring_primary.arn : null
  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? local.primary_kms_key_arn : null

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-primary-${count.index + 1}" })
}

# Secondary Aurora Cluster
resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${var.name}-${var.environment}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  port                                = var.port
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  kms_key_id                          = local.secondary_kms_key_arn
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${var.name}-${var.environment}-secondary-final"
  copy_tags_to_snapshot               = true
  preferred_maintenance_window        = var.preferred_maintenance_window
  enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports

  depends_on = [
    aws_rds_cluster_instance.primary
  ]

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-secondary-cluster" })
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                        = aws.secondary
  count                           = var.secondary_instance_count
  identifier                      = "${var.name}-${var.environment}-secondary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.secondary.id
  engine                          = aws_rds_cluster.secondary.engine
  engine_version                  = aws_rds_cluster.secondary.engine_version
  instance_class                  = var.instance_class
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  db_parameter_group_name         = aws_db_parameter_group.secondary.name
  publicly_accessible             = false
  auto_minor_version_upgrade      = var.auto_minor_version_upgrade
  preferred_maintenance_window    = var.preferred_maintenance_window
  monitoring_interval             = var.monitoring_interval
  monitoring_role_arn             = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring_secondary.arn : null
  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? local.secondary_kms_key_arn : null

  tags = merge(var.tags, { Name = "${var.name}-${var.environment}-secondary-${count.index + 1}" })
}
