data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
locals {
  prefix            = "${var.name}-${var.environment}"
  admin_secret_name = "${local.prefix}/database-admin"
  # Delegate key use to account IAM, with a separate, tightly scoped Logs grant.
  regional_key_policy = {
    for side, region in { primary = var.primary_region, secondary = var.secondary_region } : side => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "AccountAdministration"
          Effect    = "Allow"
          Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
          Action    = "kms:*"
          Resource  = "*"
        },
        {
          Sid       = "RegionalDatabaseLogs"
          Effect    = "Allow"
          Principal = { Service = "logs.${region}.amazonaws.com" }
          Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
          Resource  = "*"
          Condition = { ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.prefix}-${side}/postgresql" } }
        }
      ]
    })
  }
}
resource "aws_kms_key" "primary" {
  description             = "${local.prefix} Aurora, logs, credentials and Performance Insights in ${var.primary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.regional_key_policy.primary
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_alias" "primary" {
  name          = "alias/${local.prefix}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}
resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "${local.prefix} Aurora, logs, credentials and Performance Insights in ${var.secondary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.regional_key_policy.secondary
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.prefix}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}
resource "aws_security_group" "primary" {
  name_prefix = "${local.prefix}-db-"
  description = "PostgreSQL TLS/IAM access from approved regional EKS security groups only"
  vpc_id      = var.primary_network.vpc_id
  # No outbound rules: security groups are stateful, so replies are allowed.
}
resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = var.primary_network.client_security_group_ids
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Approved EKS client"
}
resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.prefix}-db-"
  description = "PostgreSQL TLS/IAM access from approved regional EKS security groups only"
  vpc_id      = var.secondary_network.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = var.secondary_network.client_security_group_ids
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Approved EKS client"
}
resource "aws_iam_role" "monitoring" {
  name_prefix = "${substr(local.prefix, 0, 20)}-rds-monitoring-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
resource "random_password" "admin" {
  length  = 40
  special = false
}
resource "aws_secretsmanager_secret" "admin" {
  name                    = local.admin_secret_name
  description             = "Break-glass/bootstrap only. Applications must use IAM authentication."
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30
  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
  lifecycle { prevent_destroy = true }
}
resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({
    engine   = "postgres"
    username = "dbadmin"
    password = random_password.admin.result
    host     = aws_rds_cluster.primary.endpoint
    port     = 5432
    dbname   = var.database_name
  })
}
