data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_rds_engine_version" "primary" {
  engine  = "aurora-postgresql"
  version = var.engine_version
}

data "aws_rds_engine_version" "secondary" {
  provider = aws.secondary

  engine  = "aurora-postgresql"
  version = var.engine_version
}

data "aws_rds_orderable_db_instance" "primary" {
  engine                    = "aurora-postgresql"
  engine_version            = data.aws_rds_engine_version.primary.version
  instance_class            = var.instance_class
  storage_type              = "aurora"
  supports_global_databases = true
}

data "aws_rds_orderable_db_instance" "secondary" {
  provider = aws.secondary

  engine                    = "aurora-postgresql"
  engine_version            = data.aws_rds_engine_version.secondary.version
  instance_class            = var.instance_class
  storage_type              = "aurora"
  supports_global_databases = true
}

data "aws_vpc" "primary" {
  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_subnets" "primary_database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = {
    tier = "database"
  }
}

data "aws_subnets" "secondary_database" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = {
    tier = "database"
  }
}
