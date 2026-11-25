resource "random_password" "admin" {
  length  = 40
  special = false
}
resource "random_id" "generation" { byte_length = 5 }
resource "aws_secretsmanager_secret" "admin" {
  name_prefix             = "${local.name}/bootstrap-"
  description             = "Restricted platform administrator; not an application credential"
  recovery_window_in_days = 30
  replica { region = var.recovery_region }
  tags = local.tags
}
resource "aws_secretsmanager_secret_version" "admin" {
  secret_id     = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({ username = "platform_admin", password = random_password.admin.result })
}
resource "aws_rds_global_cluster" "db" {
  global_cluster_identifier = "${local.name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = "app"
  storage_encrypted         = true
  deletion_protection       = true
  lifecycle {
    precondition {
      condition     = var.primary_region != var.recovery_region && alltrue([for r in [var.primary_region, var.recovery_region] : can(regex("^us-(east|west)-[12]$", r))])
      error_message = "Choose two distinct commercial US regions."
    }
  }
}
module "primary" {
  source         = "./regional"
  environment    = var.environment
  name           = local.name
  client_sg      = var.primary_client_security_group
  global_id      = aws_rds_global_cluster.db.id
  primary        = true
  version_string = var.engine_version
  class          = var.instance_class
  password       = random_password.admin.result
  tags           = local.tags
  topic          = var.alarm_topic_primary
  suffix         = random_id.generation.hex
}
module "recovery" {
  source         = "./regional"
  providers      = { aws = aws.dr }
  environment    = var.environment
  name           = local.name
  client_sg      = var.recovery_client_security_group
  global_id      = module.primary.ready_global_id
  primary        = false
  version_string = var.engine_version
  class          = var.instance_class
  password       = null
  tags           = local.tags
  topic          = var.alarm_topic_recovery
  suffix         = random_id.generation.hex
}
data "aws_caller_identity" "current" {}
resource "aws_iam_role_policy" "connect" {
  name   = "${local.name}-database"
  role   = var.application_role_name
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "rds-db:connect", Resource = [for region, id in { (var.primary_region) = module.primary.resource_id, (var.recovery_region) = module.recovery.resource_id } : "arn:aws:rds-db:${region}:${data.aws_caller_identity.current.account_id}:dbuser:${id}/app_runtime"] }] })
}
output "regional_endpoints" { value = { (var.primary_region) = module.primary.endpoint, (var.recovery_region) = module.recovery.endpoint } }
output "global_writer_endpoint" { value = aws_rds_global_cluster.db.endpoint }
output "global_identifier" { value = aws_rds_global_cluster.db.id }
output "admin_secret_arn" { value = aws_secretsmanager_secret.admin.arn }
