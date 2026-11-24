# ------------------------------------------------------------------------------
# Aurora PostgreSQL global database
#
# This module creates an Aurora PostgreSQL global database spanning two AWS
# regions. The primary cluster is writable and the secondary cluster is a
# cross-region Aurora replica. If the primary region fails, promoting the
# secondary cluster (a single API call via AWS/OpenTofu) restores service in
# minutes, with storage-level replication that keeps RPO at a few seconds or
# less.
# ------------------------------------------------------------------------------

locals {
  postgresql_major_version       = regex("^[0-9]+", var.engine_version)
  cluster_parameter_group_family = "aurora-postgresql${local.postgresql_major_version}"

  primary_subnet_ids = length(var.primary_subnet_ids) > 0 ? var.primary_subnet_ids : tolist(data.aws_subnets.primary_database[0].ids)

  secondary_subnet_ids = length(var.secondary_subnet_ids) > 0 ? var.secondary_subnet_ids : tolist(data.aws_subnets.secondary_database[0].ids)

  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      ManagedBy   = "opentofu"
      Service     = var.name
    }
  )
}

# ------------------------------------------------------------------------------
# Existing network discovery
#
# The network team already owns one VPC per environment in each region and tags
# the private database subnets with `tier = database`. Explicit subnet IDs can
# be provided instead, which keeps this module plan-safe in environments where
# the subnets have not yet been created.
# ------------------------------------------------------------------------------

data "aws_subnets" "primary_database" {
  count    = length(var.primary_subnet_ids) > 0 ? 0 : 1
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [var.primary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = [var.database_subnet_tag_value]
  }
}

data "aws_subnets" "secondary_database" {
  count    = length(var.secondary_subnet_ids) > 0 ? 0 : 1
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [var.secondary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = [var.database_subnet_tag_value]
  }
}

# ------------------------------------------------------------------------------
# Encryption keys
# ------------------------------------------------------------------------------

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "Aurora PostgreSQL storage encryption key for ${var.name}-${var.environment} (primary)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/${var.name}-${var.environment}-primary"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora PostgreSQL storage encryption key for ${var.name}-${var.environment} (secondary)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = local.common_tags
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${var.name}-${var.environment}-secondary"
  target_key_id = aws_kms_key.secondary.key_id
}

# ------------------------------------------------------------------------------
# Master credentials
# ------------------------------------------------------------------------------

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  provider = aws.primary

  name        = "${var.name}-${var.environment}-aurora-master"
  description = "Aurora PostgreSQL master credentials for ${var.name} (${var.environment})"
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "master" {
  provider = aws.primary

  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "postgres"
    host     = aws_rds_cluster.primary.endpoint
    port     = aws_rds_cluster.primary.port
    dbname   = var.database_name
  })
}

# ------------------------------------------------------------------------------
# Security groups
# ------------------------------------------------------------------------------

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${var.name}-${var.environment}-primary-aurora"
  description = "Aurora PostgreSQL access for ${var.name} ${var.environment} primary"
  vpc_id      = var.primary_vpc_id
  tags        = merge(local.common_tags, { Name = "${var.name}-${var.environment}-primary-aurora" })

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${var.name}-${var.environment}-secondary-aurora"
  description = "Aurora PostgreSQL access for ${var.name} ${var.environment} secondary"
  vpc_id      = var.secondary_vpc_id
  tags        = merge(local.common_tags, { Name = "${var.name}-${var.environment}-secondary-aurora" })

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "primary_cidr_ingress" {
  for_each = toset(var.allowed_cidr_blocks)
  provider = aws.primary

  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL from ${each.value}"
}

resource "aws_security_group_rule" "primary_sg_ingress" {
  for_each = toset(var.allowed_security_group_ids)
  provider = aws.primary

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.primary.id
  description              = "PostgreSQL from ${each.value}"
}

resource "aws_security_group_rule" "secondary_cidr_ingress" {
  for_each = toset(var.allowed_cidr_blocks)
  provider = aws.secondary

  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL from ${each.value}"
}

resource "aws_security_group_rule" "secondary_sg_ingress" {
  for_each = toset(var.allowed_security_group_ids)
  provider = aws.secondary

  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.secondary.id
  description              = "PostgreSQL from ${each.value}"
}

# ------------------------------------------------------------------------------
# DB subnet groups
# ------------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name       = "${var.name}-${var.environment}-primary"
  subnet_ids = local.primary_subnet_ids
  tags       = merge(local.common_tags, { Name = "${var.name}-${var.environment}-primary" })
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name       = "${var.name}-${var.environment}-secondary"
  subnet_ids = local.secondary_subnet_ids
  tags       = merge(local.common_tags, { Name = "${var.name}-${var.environment}-secondary" })
}

# ------------------------------------------------------------------------------
# Parameter groups
# ------------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name        = "${var.name}-${var.environment}-primary"
  family      = local.cluster_parameter_group_family
  description = "Aurora PostgreSQL cluster parameters for ${var.name} ${var.environment} primary"
  tags        = local.common_tags

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${var.name}-${var.environment}-secondary"
  family      = local.cluster_parameter_group_family
  description = "Aurora PostgreSQL cluster parameters for ${var.name} ${var.environment} secondary"
  tags        = local.common_tags

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

# ------------------------------------------------------------------------------
# Enhanced monitoring role
# ------------------------------------------------------------------------------

resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  provider = aws.primary

  name = "${var.name}-${var.environment}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  provider = aws.primary

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ------------------------------------------------------------------------------
# Aurora global database
# ------------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = "${var.name}-${var.environment}"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  deletion_protection       = var.deletion_protection
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier = "${var.name}-${var.environment}-primary"
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = random_password.master.result

  engine         = "aurora-postgresql"
  engine_mode    = "provisioned"
  engine_version = var.engine_version
  port           = 5432

  global_cluster_identifier       = aws_rds_global_cluster.this.id
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = "${var.name}-${var.environment}-primary-final"
  copy_tags_to_snapshot               = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  iam_database_authentication_enabled = true
  apply_immediately                   = var.apply_immediately

  tags = local.common_tags
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier = "${var.name}-${var.environment}-secondary"

  engine         = "aurora-postgresql"
  engine_mode    = "provisioned"
  engine_version = var.engine_version

  global_cluster_identifier       = aws_rds_global_cluster.this.id
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = "${var.name}-${var.environment}-secondary-final"
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports     = ["postgresql"]
  iam_database_authentication_enabled = true
  apply_immediately                   = var.apply_immediately

  depends_on = [aws_rds_cluster.primary]

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# Database instances
# ------------------------------------------------------------------------------

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  provider = aws.primary

  identifier         = "${var.name}-${var.environment}-primary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version

  publicly_accessible        = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  performance_insights_enabled = var.performance_insights_enabled

  monitoring_interval = var.monitoring_interval > 0 ? var.monitoring_interval : 0
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  tags = local.common_tags
}

resource "aws_rds_cluster_instance" "secondary" {
  count = var.secondary_instance_count

  provider = aws.secondary

  identifier         = "${var.name}-${var.environment}-secondary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = var.instance_class
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version

  publicly_accessible        = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  performance_insights_enabled = var.performance_insights_enabled

  monitoring_interval = var.monitoring_interval > 0 ? var.monitoring_interval : 0
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  tags = local.common_tags
}
