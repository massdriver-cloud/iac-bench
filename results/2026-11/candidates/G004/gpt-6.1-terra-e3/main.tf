terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" { region = var.primary_region }
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}
locals {
  name          = "${var.service_name}-${var.environment}"
  vpc_name      = "apps-${var.environment}"
  tags          = merge(var.tags, { Service = var.service_name, Environment = var.environment, ManagedBy = "OpenTofu" })
  primary_azs   = sort(distinct([for s in data.aws_subnet.primary : s.availability_zone]))
  secondary_azs = sort(distinct([for s in data.aws_subnet.secondary : s.availability_zone]))
}
data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}
data "aws_vpc" "secondary" {
  provider = aws.secondary
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}
data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
data "aws_subnets" "secondary" {
  provider = aws.secondary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
data "aws_subnet" "primary" {
  for_each = toset(data.aws_subnets.primary.ids)
  id       = each.value
}
data "aws_subnet" "secondary" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary.ids)
  id       = each.value
}
resource "aws_db_subnet_group" "primary" {
  name       = local.name
  subnet_ids = data.aws_subnets.primary.ids
  tags       = local.tags
  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2
      error_message = "The primary VPC needs database-tagged subnets in at least two availability zones."
    }
  }
}
resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = local.name
  subnet_ids = data.aws_subnets.secondary.ids
  tags       = local.tags
  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2
      error_message = "The secondary VPC needs database-tagged subnets in at least two availability zones."
    }
  }
}
resource "aws_security_group" "primary" {
  name        = "${local.name}-database"
  description = "PostgreSQL access from approved application security groups"
  vpc_id      = data.aws_vpc.primary.id
  tags        = local.tags
}
resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-database"
  description = "PostgreSQL access from approved application security groups"
  vpc_id      = data.aws_vpc.secondary.id
  tags        = local.tags
}
resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = var.primary_client_security_group_ids
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  tags                         = local.tags
}
resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = var.secondary_client_security_group_ids
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  tags                         = local.tags
}
resource "aws_rds_cluster_parameter_group" "primary" {
  name   = "${local.name}-pg16"
  family = "aurora-postgresql16"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  tags = local.tags
}
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary
  name     = "${local.name}-pg16"
  family   = "aurora-postgresql16"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  tags = local.tags
}
resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.name}-primary/postgresql"
  retention_in_days = 90
  tags              = local.tags
}
resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.name}-secondary/postgresql"
  retention_in_days = 90
  tags              = local.tags
}
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = true
  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "Primary and secondary must be different regions."
    }
  }
}
resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.name}-primary"
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  database_name                       = var.database_name
  master_username                     = var.master_username
  master_password                     = var.master_password
  iam_database_authentication_enabled = true
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  storage_encrypted                   = true
  backup_retention_period             = 35
  preferred_backup_window             = "03:00-03:30"
  preferred_maintenance_window        = "sun:05:00-sun:05:30"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = true
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.name}-primary-final"
  tags                                = local.tags
  depends_on                          = [aws_cloudwatch_log_group.primary, aws_secretsmanager_secret_version.admin]
}
resource "aws_rds_cluster_instance" "primary" {
  count                        = 2
  identifier                   = "${local.name}-primary-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.primary.id
  engine                       = aws_rds_cluster.primary.engine
  engine_version               = var.engine_version
  instance_class               = var.instance_class
  availability_zone            = try(local.primary_azs[count.index], null)
  db_subnet_group_name         = aws_db_subnet_group.primary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = false
  performance_insights_enabled = true
  tags                         = local.tags
}
resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.name}-secondary"
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  preferred_backup_window             = "03:00-03:30"
  preferred_maintenance_window        = "sun:05:00-sun:05:30"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = true
  copy_tags_to_snapshot               = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.name}-secondary-final"
  tags                                = local.tags
  depends_on                          = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]
}
resource "aws_rds_cluster_instance" "secondary" {
  provider                     = aws.secondary
  count                        = 2
  identifier                   = "${local.name}-secondary-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.secondary.id
  engine                       = aws_rds_cluster.secondary.engine
  engine_version               = var.engine_version
  instance_class               = var.instance_class
  availability_zone            = try(local.secondary_azs[count.index], null)
  db_subnet_group_name         = aws_db_subnet_group.secondary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = false
  performance_insights_enabled = true
  tags                         = local.tags
}
