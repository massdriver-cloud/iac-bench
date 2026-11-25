terraform {
  required_version = ">= 1.6.0"
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
  cluster_identifier = "${var.environment}-${var.service_name}-aurora"
  iam_db_role_bindings = {
    for pair in flatten([
      for username, role_names in var.iam_db_user_roles : [
        for role_name in role_names : {
          key       = "${username}-${role_name}"
          username  = username
          role_name = role_name
        }
      ]
    ]) : pair.key => { username = pair.username, role_name = pair.role_name }
  }
}

data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = [var.environment]
  }
}
data "aws_vpc" "secondary" {
  provider = aws.secondary
  filter {
    name   = "tag:Name"
    values = [var.environment]
  }
}
data "aws_subnets" "primary_database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
data "aws_subnets" "secondary_database" {
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

resource "aws_kms_key" "primary" {
  description             = "Aurora storage and log encryption for ${local.cluster_identifier}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = var.tags
}
resource "aws_kms_alias" "primary" {
  name          = "alias/${local.cluster_identifier}"
  target_key_id = aws_kms_key.primary.key_id
}
resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora storage and log encryption for ${local.cluster_identifier}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = var.tags
}
resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.cluster_identifier}"
  target_key_id = aws_kms_key.secondary.key_id
}

resource "aws_cloudwatch_log_group" "primary_postgresql" {
  name              = "/aws/rds/cluster/${local.cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn
  tags              = var.tags
}
resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.cluster_identifier}-dr/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn
  tags              = var.tags
}

resource "aws_db_subnet_group" "primary" {
  name        = "${local.cluster_identifier}-db"
  subnet_ids  = data.aws_subnets.primary_database.ids
  description = "Private database subnets for ${local.cluster_identifier}"
  tags        = var.tags
  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary_database.ids) >= 2
      error_message = "The primary VPC must have at least two subnets tagged tier=database, preferably in distinct Availability Zones."
    }
  }
}
resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.cluster_identifier}-dr-db"
  subnet_ids  = data.aws_subnets.secondary_database.ids
  description = "Private database subnets for ${local.cluster_identifier} DR"
  tags        = var.tags
  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary_database.ids) >= 2
      error_message = "The secondary VPC must have at least two subnets tagged tier=database, preferably in distinct Availability Zones."
    }
  }
}

resource "aws_security_group" "primary" {
  name        = "${local.cluster_identifier}-db"
  description = "Private PostgreSQL access from approved EKS security groups"
  vpc_id      = data.aws_vpc.primary.id
  tags        = merge(var.tags, { Name = "${local.cluster_identifier}-db" })
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow database-initiated responses and AWS service traffic"
  }
}
resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.cluster_identifier}-dr-db"
  description = "Private PostgreSQL access from approved EKS security groups"
  vpc_id      = data.aws_vpc.secondary.id
  tags        = merge(var.tags, { Name = "${local.cluster_identifier}-dr-db" })
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow database-initiated responses and AWS service traffic"
  }
}
resource "aws_vpc_security_group_ingress_rule" "primary_eks" {
  for_each                     = toset(var.primary_eks_security_group_ids)
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from approved EKS security group"
}
resource "aws_vpc_security_group_ingress_rule" "secondary_eks" {
  provider                     = aws.secondary
  for_each                     = toset(var.secondary_eks_security_group_ids)
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from approved EKS security group"
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.cluster_identifier
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = true
  force_destroy             = false
  tags                      = var.tags
}
