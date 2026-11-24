data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_subnets" "primary_database" {
  count = length(var.primary_database_subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.primary_vpc_id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
data "aws_subnets" "secondary_database" {
  provider = aws.secondary
  count    = length(var.secondary_database_subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [var.secondary_vpc_id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

locals {
  stem                   = "${var.name}-${var.environment}"
  primary_cluster_id     = "${local.stem}-primary"
  secondary_cluster_id   = "${local.stem}-secondary"
  parameter_group_family = "aurora-postgresql${split(".", var.engine_version)[0]}"
  primary_subnet_ids     = length(var.primary_database_subnet_ids) > 0 ? tolist(var.primary_database_subnet_ids) : data.aws_subnets.primary_database[0].ids
  secondary_subnet_ids   = length(var.secondary_database_subnet_ids) > 0 ? tolist(var.secondary_database_subnet_ids) : data.aws_subnets.secondary_database[0].ids
}

resource "aws_kms_key" "primary" {
  description             = "Aurora PostgreSQL ${local.stem} primary encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = { Name = "${local.stem}-aurora-primary", Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_kms_alias" "primary" {
  name          = "alias/${local.stem}-aurora-primary"
  target_key_id = aws_kms_key.primary.key_id
}
resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora PostgreSQL ${local.stem} secondary encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = { Name = "${local.stem}-aurora-secondary", Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.stem}-aurora-secondary"
  target_key_id = aws_kms_key.secondary.key_id
}

resource "aws_security_group" "primary" {
  name                   = "${local.stem}-aurora-primary"
  description            = "PostgreSQL access from approved EKS security groups only"
  vpc_id                 = var.primary_vpc_id
  revoke_rules_on_delete = true
  ingress                = []
  egress                 = []
  tags                   = { Name = "${local.stem}-aurora-primary", Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_security_group" "secondary" {
  provider               = aws.secondary
  name                   = "${local.stem}-aurora-secondary"
  description            = "PostgreSQL access from approved EKS security groups only"
  vpc_id                 = var.secondary_vpc_id
  revoke_rules_on_delete = true
  ingress                = []
  egress                 = []
  tags                   = { Name = "${local.stem}-aurora-secondary", Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_vpc_security_group_ingress_rule" "primary_eks" {
  for_each                     = var.primary_eks_security_group_ids
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS"
}
resource "aws_vpc_security_group_ingress_rule" "secondary_eks" {
  provider                     = aws.secondary
  for_each                     = var.secondary_eks_security_group_ids
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS"
}

resource "aws_db_subnet_group" "primary" {
  name        = "${local.stem}-aurora-primary"
  description = "Database-tier subnets in ${var.primary_region}"
  subnet_ids  = local.primary_subnet_ids
  lifecycle {
    precondition {
      condition     = length(local.primary_subnet_ids) >= 2
      error_message = "The primary VPC must provide database-tier subnets in at least two Availability Zones."
    }
  }
  tags = { Name = "${local.stem}-aurora-primary", Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.stem}-aurora-secondary"
  description = "Database-tier subnets in ${var.secondary_region}"
  subnet_ids  = local.secondary_subnet_ids
  lifecycle {
    precondition {
      condition     = length(local.secondary_subnet_ids) >= 2
      error_message = "The secondary VPC must provide database-tier subnets in at least two Availability Zones."
    }
  }
  tags = { Name = "${local.stem}-aurora-secondary", Environment = var.environment, ManagedBy = "OpenTofu" }
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.stem}-aurora-primary"
  family      = local.parameter_group_family
  description = "Secure PostgreSQL settings for ${local.stem} primary"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }
  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }
  tags = { Name = "${local.stem}-aurora-primary", Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.stem}-aurora-secondary"
  family      = local.parameter_group_family
  description = "Secure PostgreSQL settings for ${local.stem} secondary"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }
  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }
  tags = { Name = "${local.stem}-aurora-secondary", Environment = var.environment, ManagedBy = "OpenTofu" }
}

resource "aws_cloudwatch_log_group" "primary_postgresql" {
  name              = "/aws/rds/cluster/${local.primary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days
  tags              = { Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days
  tags              = { Environment = var.environment, ManagedBy = "OpenTofu" }
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.stem}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = true
  lifecycle { prevent_destroy = true }
  tags = { Name = "${local.stem}-global", Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = local.primary_cluster_id
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  database_name                       = var.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = "06:00-07:00"
  preferred_maintenance_window        = "sun:07:00-sun:08:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.primary_cluster_id}-final"
  apply_immediately                   = false
  depends_on                          = [aws_cloudwatch_log_group.primary_postgresql]
  lifecycle { prevent_destroy = true }
  tags = { Name = local.primary_cluster_id, Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_rds_cluster" "secondary" {
  provider                        = aws.secondary
  cluster_identifier              = local.secondary_cluster_id
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.secondary.arn
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  enabled_cloudwatch_logs_exports = ["postgresql"]
  copy_tags_to_snapshot           = true
  deletion_protection             = true
  skip_final_snapshot             = true
  apply_immediately               = false
  depends_on                      = [aws_rds_cluster.primary, aws_cloudwatch_log_group.secondary_postgresql]
  lifecycle { prevent_destroy = true }
  tags = { Name = local.secondary_cluster_id, Environment = var.environment, ManagedBy = "OpenTofu" }
}

resource "aws_rds_cluster_instance" "primary" {
  count                                 = var.primary_instance_count
  identifier                            = format("%s-%02d", local.primary_cluster_id, count.index + 1)
  cluster_identifier                    = aws_rds_cluster.primary.id
  instance_class                        = var.instance_class
  engine                                = "aurora-postgresql"
  engine_version                        = var.engine_version
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  promotion_tier                        = min(count.index, 15)
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  tags                                  = { Name = format("%s-%02d", local.primary_cluster_id, count.index + 1), Environment = var.environment, ManagedBy = "OpenTofu" }
}
resource "aws_rds_cluster_instance" "secondary" {
  provider                              = aws.secondary
  count                                 = var.secondary_instance_count
  identifier                            = format("%s-%02d", local.secondary_cluster_id, count.index + 1)
  cluster_identifier                    = aws_rds_cluster.secondary.id
  instance_class                        = var.instance_class
  engine                                = "aurora-postgresql"
  engine_version                        = var.engine_version
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  promotion_tier                        = min(count.index, 15)
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  tags                                  = { Name = format("%s-%02d", local.secondary_cluster_id, count.index + 1), Environment = var.environment, ManagedBy = "OpenTofu" }
}

resource "aws_iam_role_policy" "eks_rds_connect" {
  for_each = var.eks_iam_role_names
  name     = "${local.stem}-aurora-connect"
  role     = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["rds-db:connect"]
      Resource = [
        "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.iam_database_username}",
        "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.iam_database_username}"
      ]
    }]
  })
}
