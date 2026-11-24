data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
resource "aws_kms_key" "primary" {
  description             = "${var.name}: primary Aurora, logs, secrets and performance insights"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "AccountAdministration", Effect = "Allow", Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }, Action = "kms:*", Resource = "*" },
    { Sid = "CloudWatchLogs", Effect = "Allow", Principal = { Service = "logs.${var.primary_region}.amazonaws.com" }, Action = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"], Resource = "*", Condition = { ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${var.name}-primary/*" } } }
  ] })
}
resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "${var.name}: secondary Aurora, logs, secrets and performance insights"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "AccountAdministration", Effect = "Allow", Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }, Action = "kms:*", Resource = "*" },
    { Sid = "CloudWatchLogs", Effect = "Allow", Principal = { Service = "logs.${var.secondary_region}.amazonaws.com" }, Action = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"], Resource = "*", Condition = { ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${var.name}-secondary/*" } } }
  ] })
}
resource "aws_kms_alias" "primary" {
  name          = "alias/${var.name}-aurora-primary"
  target_key_id = aws_kms_key.primary.key_id
}
resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${var.name}-aurora-secondary"
  target_key_id = aws_kms_key.secondary.key_id
}
resource "random_password" "admin" {
  length  = 40
  special = false
}
resource "aws_secretsmanager_secret" "admin" {
  name                    = "${var.name}/aurora/bootstrap-admin"
  description             = "Break-glass and bootstrap only. Applications use IAM, not this credential."
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30
  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}
resource "aws_secretsmanager_secret_version" "admin" {
  secret_id     = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({ username = "dbadmin", password = random_password.admin.result, engine = "postgres", port = 5432, dbname = var.database_name })
}
resource "aws_iam_role" "monitoring" {
  name               = "${var.name}-rds-monitoring"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "monitoring.rds.amazonaws.com" }, Action = "sts:AssumeRole", Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:rds:*:${data.aws_caller_identity.current.account_id}:db:${var.name}-*" } } }] })
}
resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
resource "aws_iam_policy" "connect" {
  name        = "${var.name}-database-connect"
  description = "Only IAM login as ${var.application_database_user}, in either global database member"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "rds-db:connect", Resource = [
    "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.application_database_user}",
    "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.application_database_user}"
  ] }] })
}
resource "aws_iam_role_policy_attachment" "application" {
  for_each   = var.application_role_names
  role       = each.value
  policy_arn = aws_iam_policy.connect.arn
}
