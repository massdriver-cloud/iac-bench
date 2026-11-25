terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
  }
}

provider "aws" {
  region = var.primary_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

locals {
  name_prefix = "${var.environment}-${var.service_name}"
  common_tags = merge(var.tags, {
    Environment = var.environment
    Service     = var.service_name
    ManagedBy   = "OpenTofu"
  })

  # IAM role ARNs are supplied by the platform/EKS team; use their account ID
  # when constructing the narrowly-scoped rds-db:connect resource ARNs.
  iam_account_id = length(var.iam_role_arns) > 0 ? split(":", var.iam_role_arns[0])[4] : ""
  iam_db_user_resources = flatten([
    for user in var.iam_database_users : [
      "arn:aws:rds-db:${var.primary_region}:${local.iam_account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
      "arn:aws:rds-db:${var.secondary_region}:${local.iam_account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}"
    ]
  ])
  role_names = {
    for arn in var.iam_role_arns : arn => element(split("/", arn), length(split("/", arn)) - 1)
  }
}

resource "aws_kms_key" "primary" {
  description             = "Aurora encryption key for ${local.name_prefix} in ${var.primary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.common_tags
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.name_prefix}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora encryption key for ${local.name_prefix} in ${var.secondary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.common_tags
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.name_prefix}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}

resource "aws_security_group" "primary" {
  name        = "${local.name_prefix}-aurora"
  description = "PostgreSQL access from approved EKS client security groups"
  vpc_id      = var.primary_vpc_id
  tags        = merge(local.common_tags, { Name = "${local.name_prefix}-aurora" })

  dynamic "ingress" {
    for_each = toset(var.primary_eks_security_group_ids)
    content {
      description     = "PostgreSQL from EKS clients"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-aurora"
  description = "PostgreSQL access from approved EKS client security groups"
  vpc_id      = var.secondary_vpc_id
  tags        = merge(local.common_tags, { Name = "${local.name_prefix}-aurora" })

  dynamic "ingress" {
    for_each = toset(var.secondary_eks_security_group_ids)
    content {
      description     = "PostgreSQL from EKS clients"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "primary" {
  name        = "${local.name_prefix}-aurora"
  description = "Private database subnets for ${local.name_prefix}"
  subnet_ids  = var.primary_database_subnet_ids
  tags        = local.common_tags
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-aurora"
  description = "Private database subnets for ${local.name_prefix}"
  subnet_ids  = var.secondary_database_subnet_ids
  tags        = local.common_tags
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name_prefix}-aurora-pg${var.postgres_major_version}"
  family      = "aurora-postgresql${var.postgres_major_version}"
  description = "Secure PostgreSQL defaults for ${local.name_prefix}"
  tags        = local.common_tags

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-aurora-pg${var.postgres_major_version}"
  family      = "aurora-postgresql${var.postgres_major_version}"
  description = "Secure PostgreSQL defaults for ${local.name_prefix}"
  tags        = local.common_tags

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }
}

resource "aws_cloudwatch_log_group" "primary_postgresql" {
  name              = "/aws/rds/cluster/${local.name_prefix}-primary/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.name_prefix}-secondary/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn
  tags              = local.common_tags
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = true
  tags                      = local.common_tags
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.name_prefix}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  database_name                       = var.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  backup_retention_period             = 35
  preferred_backup_window             = var.backup_window
  preferred_maintenance_window        = var.maintenance_window
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.name_prefix}-primary-final"
  apply_immediately                   = false
  tags                                = local.common_tags

  depends_on = [aws_cloudwatch_log_group.primary_postgresql]
}

resource "aws_rds_cluster_instance" "primary" {
  identifier                   = "${local.name_prefix}-primary-1"
  cluster_identifier           = aws_rds_cluster.primary.id
  instance_class               = var.instance_class
  engine                       = "aurora-postgresql"
  engine_version               = var.engine_version
  db_subnet_group_name         = aws_db_subnet_group.primary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  performance_insights_enabled = true
  promotion_tier               = 0
  tags                         = local.common_tags
}

resource "aws_rds_cluster" "secondary" {
  provider                        = aws.secondary
  cluster_identifier              = "${local.name_prefix}-secondary"
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.secondary.arn
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  backup_retention_period         = 35
  preferred_backup_window         = var.backup_window
  preferred_maintenance_window    = var.maintenance_window
  enabled_cloudwatch_logs_exports = ["postgresql"]
  copy_tags_to_snapshot           = true
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${local.name_prefix}-secondary-final"
  apply_immediately               = false
  tags                            = local.common_tags

  # AWS requires the Global Database primary to exist before adding a secondary.
  depends_on = [aws_cloudwatch_log_group.secondary_postgresql, aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                     = aws.secondary
  identifier                   = "${local.name_prefix}-secondary-1"
  cluster_identifier           = aws_rds_cluster.secondary.id
  instance_class               = var.instance_class
  engine                       = "aurora-postgresql"
  engine_version               = var.engine_version
  db_subnet_group_name         = aws_db_subnet_group.secondary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  performance_insights_enabled = true
  promotion_tier               = 0
  tags                         = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "global_replication_lag" {
  provider            = aws.secondary
  alarm_name          = "${local.name_prefix}-global-replication-lag"
  alarm_description   = "Aurora Global Database replication lag is above five seconds"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "AuroraGlobalDBReplicationLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 5000
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }
  alarm_actions = var.alarm_sns_topic_arns
  ok_actions    = var.alarm_sns_topic_arns
  tags          = local.common_tags
}

resource "aws_iam_policy" "database_connect" {
  count       = length(var.iam_role_arns) > 0 && length(var.iam_database_users) > 0 ? 1 : 0
  name        = "${local.name_prefix}-aurora-connect"
  description = "Permit approved EKS roles to authenticate as configured Aurora PostgreSQL IAM users"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds-db:connect"]
      Resource = local.iam_db_user_resources
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "database_connect" {
  for_each   = length(var.iam_role_arns) > 0 && length(var.iam_database_users) > 0 ? local.role_names : {}
  role       = each.value
  policy_arn = aws_iam_policy.database_connect[0].arn
}
