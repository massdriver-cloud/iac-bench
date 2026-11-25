resource "aws_rds_global_cluster" "database" {
  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = true
  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region && alltrue([for region in [var.primary_region, var.secondary_region] : can(regex("^us-(east|west)-[12]$", region))])
      error_message = "Choose two distinct commercial US AWS regions."
    }
  }
}
module "primary" {
  source           = "./regional"
  name             = "${local.name}-a"
  database         = var.service
  environment      = var.environment
  global_id        = aws_rds_global_cluster.database.id
  client_group     = var.clients.primary
  engine_version   = var.engine_version
  instance_class   = var.instance_class
  password         = var.bootstrap_password
  password_version = var.password_version
}
module "secondary" {
  source         = "./regional"
  providers      = { aws = aws.dr }
  name           = "${local.name}-b"
  database       = var.service
  environment    = var.environment
  global_id      = module.primary.ready_global_id
  client_group   = var.clients.secondary
  engine_version = var.engine_version
  instance_class = var.instance_class
  source_region  = var.primary_region
}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
resource "aws_iam_role_policy" "connect" {
  name = "${local.name}-connect"
  role = var.application_role
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "rds-db:connect", Resource = [for region, id in {
      (var.primary_region)   = module.primary.resource_id
      (var.secondary_region) = module.secondary.resource_id
    } : "arn:${data.aws_partition.current.partition}:rds-db:${region}:${data.aws_caller_identity.current.account_id}:dbuser:${id}/app_user"] }]
  })
}
resource "aws_cloudwatch_metric_alarm" "lag" {
  provider            = aws.dr
  alarm_name          = "${local.name}-global-replication-lag"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = "${local.name}-b" }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 3000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
}
output "global_writer_endpoint" { value = aws_rds_global_cluster.database.endpoint }
output "regional_endpoints" {
  value = { primary = module.primary.endpoint, secondary = module.secondary.endpoint }
}
output "database_name" { value = var.service }
