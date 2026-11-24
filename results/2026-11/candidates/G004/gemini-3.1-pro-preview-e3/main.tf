data "aws_vpc" "primary" {
  provider = aws
  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_subnets" "primary" {
  provider = aws
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  tags = {
    tier = "database"
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  tags = {
    tier = "database"
  }
}

resource "aws_kms_key" "primary" {
  provider            = aws
  description         = "KMS key for primary Aurora cluster ${var.service_name}"
  enable_key_rotation = true
}

resource "aws_kms_key" "secondary" {
  provider            = aws.secondary
  description         = "KMS key for secondary Aurora cluster ${var.service_name}"
  enable_key_rotation = true
}

resource "aws_db_subnet_group" "primary" {
  provider   = aws
  name       = "${var.service_name}-${var.environment}-primary"
  subnet_ids = data.aws_subnets.primary.ids
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${var.service_name}-${var.environment}-secondary"
  subnet_ids = data.aws_subnets.secondary.ids
}

resource "aws_security_group" "primary" {
  provider    = aws
  name        = "${var.service_name}-${var.environment}-primary-db"
  vpc_id      = data.aws_vpc.primary.id
  description = "Security group for primary Aurora cluster"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.primary.cidr_block]
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.service_name}-${var.environment}-secondary-db"
  vpc_id      = data.aws_vpc.secondary.id
  description = "Security group for secondary Aurora cluster"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.secondary.cidr_block]
  }
}

resource "aws_rds_global_cluster" "this" {
  provider                  = aws
  global_cluster_identifier = "${var.service_name}-${var.environment}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.service_name
  storage_encrypted         = true
}

resource "aws_rds_cluster" "primary" {
  provider                  = aws
  cluster_identifier        = "${var.service_name}-${var.environment}-primary"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary.id]

  database_name               = var.service_name
  master_username             = "dbadmin"
  manage_master_user_password = true

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  iam_database_authentication_enabled = true

  skip_final_snapshot = true
}

resource "aws_rds_cluster_instance" "primary" {
  provider             = aws
  count                = 2
  identifier           = "${var.service_name}-${var.environment}-primary-${count.index}"
  cluster_identifier   = aws_rds_cluster.primary.id
  engine               = aws_rds_cluster.primary.engine
  engine_version       = aws_rds_cluster.primary.engine_version
  instance_class       = var.instance_class
  db_subnet_group_name = aws_db_subnet_group.primary.name
}

resource "aws_rds_cluster" "secondary" {
  provider                  = aws.secondary
  cluster_identifier        = "${var.service_name}-${var.environment}-secondary"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.secondary.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  iam_database_authentication_enabled = true

  skip_final_snapshot = true

  depends_on = [
    aws_rds_cluster_instance.primary
  ]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider             = aws.secondary
  count                = 1
  identifier           = "${var.service_name}-${var.environment}-secondary-${count.index}"
  cluster_identifier   = aws_rds_cluster.secondary.id
  engine               = aws_rds_cluster.secondary.engine
  engine_version       = aws_rds_cluster.secondary.engine_version
  instance_class       = var.instance_class
  db_subnet_group_name = aws_db_subnet_group.secondary.name
}
