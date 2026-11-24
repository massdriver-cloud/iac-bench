resource "aws_rds_global_cluster" "this" {
  provider                  = aws
  global_cluster_identifier = "${local.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  deletion_protection       = var.deletion_protection
}
