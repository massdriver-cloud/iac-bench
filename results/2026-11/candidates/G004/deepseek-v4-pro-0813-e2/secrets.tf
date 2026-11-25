#
# Managed master credentials.
#
# Aurora global databases only accept master credentials on the primary cluster.
# Secrets Manager generates the password, and the module stores the complete
# credential document in Secrets Manager so services and operators never need to
# put a long-lived password in tfvars or the state file.
#

data "aws_secretsmanager_random_password" "master" {
  provider            = aws.primary
  password_length     = 32
  exclude_punctuation = true
}

resource "aws_secretsmanager_secret" "master" {
  provider = aws.primary

  name                    = "${local.prefix}-aurora-master"
  description             = "Master credentials for ${var.service_name} (${var.environment}) Aurora PostgreSQL"
  recovery_window_in_days = 7

  tags = local.default_tags
}

resource "aws_secretsmanager_secret_version" "master" {
  provider  = aws.primary
  secret_id = aws_secretsmanager_secret.master.id

  secret_string = jsonencode({
    username = var.master_username
    password = data.aws_secretsmanager_random_password.master.random_password
    engine   = "aurora-postgresql"
    host     = aws_rds_cluster.primary.endpoint
    port     = var.port
  })

  lifecycle {
    # Secrets Manager returns a fresh random value every time the data source is
    # read. Once the first version is created we keep it as the stable master
    # credential for the cluster and manage rotations outside Terraform.
    ignore_changes = [secret_string]
  }
}