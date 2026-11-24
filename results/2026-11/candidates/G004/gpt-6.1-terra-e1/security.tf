resource "aws_kms_key" "primary" {
  description             = "${local.name} primary Aurora and secret encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "${local.name} secondary Aurora and secret encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
resource "random_password" "master" {
  length  = 40
  special = false
}
resource "aws_secretsmanager_secret" "master" {
  name                    = "${local.name}/aurora-master"
  description             = "Aurora administrator credentials; use IAM database authentication or dedicated application users for services"
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30
  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}
resource "aws_secretsmanager_secret_version" "master" {
  secret_id     = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({ username = var.master_username, password = random_password.master.result })
}
