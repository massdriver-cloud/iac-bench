###############################################################################
# Per-region foundations (network placement, KMS key, parameters, logs, alarm)
###############################################################################

module "primary" {
  source = "./modules/regional"

  name                          = local.name
  region                        = var.primary_region
  account_id                    = data.aws_caller_identity.current.account_id
  partition                     = data.aws_partition.current.partition
  cluster_identifier            = local.cluster_identifiers.primary
  engine                        = local.engine
  engine_version                = var.engine_version
  instance_class                = var.instance_class
  vpc_name                      = local.vpc_name
  port                          = local.port
  client_security_group_ids     = lookup(var.client_security_group_ids, var.primary_region, [])
  parameter_group_family        = local.parameter_group_family
  cluster_parameters            = local.cluster_parameters
  log_retention_days            = var.log_retention_days
  replication_lag_alarm_seconds = var.replication_lag_alarm_seconds
  alarm_sns_topic_arns          = lookup(var.alarm_sns_topic_arns, var.primary_region, [])
}

module "secondary" {
  source = "./modules/regional"

  providers = {
    aws = aws.secondary
  }

  name                          = local.name
  region                        = var.secondary_region
  account_id                    = data.aws_caller_identity.current.account_id
  partition                     = data.aws_partition.current.partition
  cluster_identifier            = local.cluster_identifiers.secondary
  engine                        = local.engine
  engine_version                = var.engine_version
  instance_class                = var.instance_class
  vpc_name                      = local.vpc_name
  port                          = local.port
  client_security_group_ids     = lookup(var.client_security_group_ids, var.secondary_region, [])
  parameter_group_family        = local.parameter_group_family
  cluster_parameters            = local.cluster_parameters
  log_retention_days            = var.log_retention_days
  replication_lag_alarm_seconds = var.replication_lag_alarm_seconds
  alarm_sns_topic_arns          = lookup(var.alarm_sns_topic_arns, var.secondary_region, [])
}

###############################################################################
# Break-glass administrator credentials
###############################################################################

# Services authenticate with IAM; this password exists for initial setup and
# emergencies. It is stored in Secrets Manager under the regional KMS keys and
# replicated to the standby region so it is still readable when the primary
# region is down.
resource "random_password" "master" {
  length           = 40
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?" # RDS rejects / @ " and spaces
}

resource "aws_secretsmanager_secret" "master" {
  name        = "rds/${local.name}/master"
  description = "Break-glass administrator credentials for the ${local.name} Aurora global database"
  kms_key_id  = module.primary.kms_key_arn

  replica {
    region     = var.secondary_region
    kms_key_id = module.secondary.kms_key_arn
  }
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id

  secret_string = jsonencode({
    engine   = "postgres"
    username = var.master_username
    password = random_password.master.result
    host     = aws_rds_global_cluster.this.endpoint
    port     = local.port
    dbname   = local.database_name
  })
}

###############################################################################
# Enhanced monitoring role (IAM is global, shared by both regions)
###############################################################################

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${local.name}-aurora-monitoring"
  description        = "Lets RDS publish OS-level metrics for the ${local.name} database instances"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

###############################################################################
# Global database
###############################################################################

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = local.engine
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be different regions - the point of this module is surviving the loss of one."
    }

    precondition {
      condition     = length(setsubtract(keys(var.client_security_group_ids), [var.primary_region, var.secondary_region])) == 0
      error_message = "client_security_group_ids may only be keyed by primary_region and secondary_region."
    }

    precondition {
      condition     = length(setsubtract(keys(var.alarm_sns_topic_arns), [var.primary_region, var.secondary_region])) == 0
      error_message = "alarm_sns_topic_arns may only be keyed by primary_region and secondary_region."
    }
  }
}

###############################################################################
# Primary region: the cluster that takes writes in normal operation
###############################################################################

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = local.cluster_identifiers.primary
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  database_name  = local.database_name
  port           = local.port

  master_username                     = var.master_username
  master_password                     = random_password.master.result
  iam_database_authentication_enabled = true

  db_subnet_group_name            = module.primary.db_subnet_group_name
  vpc_security_group_ids          = [module.primary.security_group_id]
  db_cluster_parameter_group_name = module.primary.cluster_parameter_group_name

  storage_encrypted = true
  kms_key_id        = module.primary.kms_key_arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.cluster_identifiers.primary}-final"
  deletion_protection          = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]
  apply_immediately               = var.apply_immediately

  # The log group (with retention and encryption) must exist before RDS
  # starts exporting, or RDS creates an unencrypted never-expiring one.
  depends_on = [module.primary]

  lifecycle {
    ignore_changes = [
      # Flips when the regions swap roles in a switchover / failover.
      replication_source_identifier,
      # Version upgrades are driven through aws_rds_global_cluster.
      engine_version,
    ]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.instances_per_region

  identifier         = "${local.cluster_identifiers.primary}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = module.primary.db_subnet_group_name
  publicly_accessible  = false

  # Minor versions of a global database are upgraded for both regions together
  # through engine_version, never instance by instance.
  auto_minor_version_upgrade = false

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = module.primary.kms_key_arn
  performance_insights_retention_period = 7

  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true
  apply_immediately            = var.apply_immediately

  depends_on = [aws_iam_role_policy_attachment.monitoring]

  lifecycle {
    ignore_changes = [engine_version]
  }
}

###############################################################################
# Secondary region: continuously replicated warm standby
###############################################################################

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.cluster_identifiers.secondary
  global_cluster_identifier = aws_rds_global_cluster.this.id
  source_region             = var.primary_region

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  port           = local.port

  # No database name or master credentials here: both replicate from the
  # primary cluster.
  iam_database_authentication_enabled = true

  # Services running in this region connect to this local cluster; their
  # writes are forwarded to the writer region over the AWS backbone, so no
  # cross-region network path is needed.
  enable_global_write_forwarding = true

  db_subnet_group_name            = module.secondary.db_subnet_group_name
  vpc_security_group_ids          = [module.secondary.security_group_id]
  db_cluster_parameter_group_name = module.secondary.cluster_parameter_group_name

  storage_encrypted = true
  kms_key_id        = module.secondary.kms_key_arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.cluster_identifiers.secondary}-final"
  deletion_protection          = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]
  apply_immediately               = var.apply_immediately

  # A secondary can only attach once the primary cluster has a running writer.
  depends_on = [
    module.secondary,
    aws_rds_cluster_instance.primary,
  ]

  lifecycle {
    ignore_changes = [
      replication_source_identifier,
      engine_version,
    ]
  }
}

# The standby region runs full-size instances at all times. A "headless"
# secondary would be cheaper, but instances take longer to create than the
# recovery-time target allows, and capacity may be scarce during a regional
# event.
resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.instances_per_region

  identifier         = "${local.cluster_identifiers.secondary}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = module.secondary.db_subnet_group_name
  publicly_accessible  = false

  auto_minor_version_upgrade = false

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = module.secondary.kms_key_arn
  performance_insights_retention_period = 7

  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true
  apply_immediately            = var.apply_immediately

  depends_on = [aws_iam_role_policy_attachment.monitoring]

  lifecycle {
    ignore_changes = [engine_version]
  }
}

###############################################################################
# IAM database authentication for the services
###############################################################################

# Grants login as app_db_username on BOTH regional clusters, so a pod's role
# keeps working whichever region it runs in and whichever region is the writer.
data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "ConnectAsApplicationUser"
    actions = ["rds-db:connect"]

    resources = [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.app_db_username}",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.app_db_username}",
    ]
  }
}

resource "aws_iam_policy" "db_connect" {
  name        = "${local.name}-aurora-connect"
  description = "IAM database authentication as ${var.app_db_username} on the ${local.name} Aurora global database"
  policy      = data.aws_iam_policy_document.db_connect.json
}

resource "aws_iam_role_policy_attachment" "db_connect" {
  for_each = toset(var.app_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}
