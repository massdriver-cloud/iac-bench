# The master password is generated here and never appears in outputs. It is
# stored in Secrets Manager in BOTH regions so services can authenticate
# immediately after a regional failover — there is no time to copy secrets
# around during an incident.
resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "primary" {
  name        = "${local.prefix}-db-credentials"
  description = "Master credentials for the ${local.prefix} Aurora PostgreSQL cluster (primary region, read-write)"
  kms_key_id  = aws_kms_key.primary.arn
}

resource "aws_secretsmanager_secret_version" "primary" {
  secret_id = aws_secretsmanager_secret.primary.id

  secret_string = jsonencode({
    engine   = "postgresql"
    host     = aws_rds_cluster.primary.endpoint
    port     = local.engine_port
    dbname   = local.database_name
    username = var.master_username
    password = random_password.master.result
  })
}

resource "aws_secretsmanager_secret" "secondary" {
  provider = aws.secondary

  name        = "${local.prefix}-db-credentials"
  description = "Master credentials for the ${local.prefix} Aurora PostgreSQL cluster (secondary region; read-only until regional failover promotes it)"
  kms_key_id  = aws_kms_key.secondary.arn
}

resource "aws_secretsmanager_secret_version" "secondary" {
  provider = aws.secondary

  secret_id = aws_secretsmanager_secret.secondary.id

  secret_string = jsonencode({
    engine   = "postgresql"
    host     = aws_rds_cluster.secondary.endpoint
    port     = local.engine_port
    dbname   = local.database_name
    username = var.master_username
    password = random_password.master.result
  })
}
