resource "aws_secretsmanager_secret" "primary" {
  provider                = aws
  name                    = "${local.name_prefix}-db-credentials"
  description             = "Database master credentials for ${local.name_prefix} (primary region)"
  kms_key_id              = local.primary_kms_key_arn
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "primary" {
  provider  = aws
  secret_id = aws_secretsmanager_secret.primary.id
  secret_string = jsonencode({
    engine      = "aurora-postgresql"
    host        = aws_rds_cluster.primary.endpoint
    reader_host = aws_rds_cluster.primary.reader_endpoint
    port        = 5432
    username    = var.master_username
    password    = var.master_password
    database    = local.database_name
  })
}

resource "aws_secretsmanager_secret" "secondary" {
  provider                = aws.secondary
  name                    = "${local.name_prefix}-db-credentials"
  description             = "Database master credentials for ${local.name_prefix} (secondary region)"
  kms_key_id              = local.secondary_kms_key_arn
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "secondary" {
  provider  = aws.secondary
  secret_id = aws_secretsmanager_secret.secondary.id
  secret_string = jsonencode({
    engine      = "aurora-postgresql"
    host        = aws_rds_cluster.secondary.endpoint
    reader_host = aws_rds_cluster.secondary.reader_endpoint
    port        = 5432
    username    = var.master_username
    password    = var.master_password
    database    = local.database_name
  })
}
