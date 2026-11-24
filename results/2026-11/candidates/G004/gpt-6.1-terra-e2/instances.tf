resource "aws_rds_cluster_instance" "primary" {
  count                           = 2
  identifier                      = "${local.id}-primary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.primary.id
  instance_class                  = var.instance_class
  availability_zone               = try(local.primary_azs[count.index], null)
  engine                          = aws_rds_cluster.primary.engine
  engine_version                  = var.engine_version
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  publicly_accessible             = false
  auto_minor_version_upgrade      = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary.arn
  tags                            = local.tags
  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2
      error_message = "Database subnets in the primary region must span at least two availability zones."
    }
  }
}
resource "aws_rds_cluster_instance" "secondary" {
  provider                        = aws.secondary
  count                           = 2
  identifier                      = "${local.id}-secondary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.secondary.id
  instance_class                  = var.instance_class
  availability_zone               = try(local.secondary_azs[count.index], null)
  engine                          = aws_rds_cluster.secondary.engine
  engine_version                  = var.engine_version
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  publicly_accessible             = false
  auto_minor_version_upgrade      = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary.arn
  tags                            = local.tags
  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2
      error_message = "Database subnets in the secondary region must span at least two availability zones."
    }
  }
}
