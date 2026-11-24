data "aws_vpc" "primary" {
  tags = { Name = "apps-${var.environment}" }
}

data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  tags = { tier = "database" }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags     = { Name = "apps-${var.environment}" }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  tags = { tier = "database" }
}

resource "aws_db_subnet_group" "primary" {
  name       = "${var.service_name}-primary"
  subnet_ids = data.aws_subnets.primary.ids
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${var.service_name}-secondary"
  subnet_ids = data.aws_subnets.secondary.ids
}

resource "aws_kms_key" "primary" {
  description         = "KMS key for Aurora Primary ${var.service_name}"
  enable_key_rotation = true
}

resource "aws_kms_alias" "primary" {
  name          = "alias/aurora/${var.service_name}-primary"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider            = aws.secondary
  description         = "KMS key for Aurora Secondary ${var.service_name}"
  enable_key_rotation = true
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/aurora/${var.service_name}-secondary"
  target_key_id = aws_kms_key.secondary.key_id
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${var.service_name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${var.service_name}-primary"
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = var.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true
  skip_final_snapshot                 = true
}

resource "aws_rds_cluster_instance" "primary" {
  count                = var.instance_count
  identifier           = "${var.service_name}-primary-${count.index}"
  cluster_identifier   = aws_rds_cluster.primary.id
  instance_class       = var.instance_class
  engine               = aws_rds_cluster.primary.engine
  engine_version       = aws_rds_cluster.primary.engine_version
  db_subnet_group_name = aws_db_subnet_group.primary.name
}

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${var.service_name}-secondary"
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true
  skip_final_snapshot                 = true
  depends_on                          = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider             = aws.secondary
  count                = var.instance_count
  identifier           = "${var.service_name}-secondary-${count.index}"
  cluster_identifier   = aws_rds_cluster.secondary.id
  instance_class       = var.instance_class
  engine               = aws_rds_cluster.secondary.engine
  engine_version       = aws_rds_cluster.secondary.engine_version
  db_subnet_group_name = aws_db_subnet_group.secondary.name
}
