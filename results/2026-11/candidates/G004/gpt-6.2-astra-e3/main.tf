resource "random_password" "admin" {
  length  = 40
  special = false
}
resource "random_id" "generation" { byte_length = 4 }
resource "aws_rds_global_cluster" "db" {
  global_cluster_identifier = "${local.name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = "app"
  storage_encrypted         = true
  deletion_protection       = true
}
module "primary" {
  source          = "./regional"
  site            = var.locations.primary
  name            = local.name
  environment     = var.environment
  global_id       = aws_rds_global_cluster.db.id
  instance_class  = var.instance_class
  engine_version  = var.engine_version
  primary         = true
  password        = random_password.admin.result
  snapshot_suffix = random_id.generation.hex
}
module "secondary" {
  source          = "./regional"
  providers       = { aws = aws.secondary }
  site            = var.locations.secondary
  name            = local.name
  environment     = var.environment
  global_id       = module.primary.ready_global_id
  instance_class  = var.instance_class
  engine_version  = var.engine_version
  primary         = false
  source_region   = var.locations.primary.region
  snapshot_suffix = random_id.generation.hex
}
resource "aws_secretsmanager_secret" "admin" {
  name       = "${local.name}/aurora-admin"
  kms_key_id = module.primary.key_arn
  replica {
    region     = var.locations.secondary.region
    kms_key_id = module.secondary.key_arn
  }
}
resource "aws_secretsmanager_secret_version" "admin" {
  secret_id     = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({ username = "dbadmin", password = random_password.admin.result, dbname = "app", port = 5432, engine = "postgres" })
}
data "aws_caller_identity" "current" {}
resource "aws_iam_role_policy" "connect" {
  for_each = var.client_roles
  role     = each.key
  name     = "${local.name}-connect"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "rds-db:connect", Resource = [
    "arn:aws:rds-db:${var.locations.primary.region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.primary.resource_id}/${each.value}",
    "arn:aws:rds-db:${var.locations.secondary.region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.secondary.resource_id}/${each.value}"
  ] }] })
}
resource "aws_cloudwatch_metric_alarm" "replication" {
  provider            = aws.secondary
  alarm_name          = "${local.name}-global-rpo-lag"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = module.secondary.cluster_id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 3000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.locations.secondary.alarm_topic]
  ok_actions          = [var.locations.secondary.alarm_topic]
}
output "global_cluster_id" { value = aws_rds_global_cluster.db.id }
output "global_writer_endpoint" { value = aws_rds_global_cluster.db.endpoint }
output "regional_endpoints" {
  value = { for k, m in { primary = module.primary, secondary = module.secondary } : k => { cluster = m.writer_endpoint, reader = m.reader_endpoint } }
}
output "admin_secret_arn" { value = aws_secretsmanager_secret.admin.arn }
