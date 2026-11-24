# ---------------------------------------------------------------------------
# Master credentials
#
# RDS-managed master passwords are not supported for Aurora Global Databases,
# so the module generates the password and stores it in Secrets Manager,
# encrypted with the module's CMK and replicated to the secondary region so it
# is available after a regional failover. Applications should authenticate
# with IAM database authentication (enabled below), not with this user.
# ---------------------------------------------------------------------------

resource "random_password" "master" {
  length           = 40
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  name                    = "rds/${local.name}/master"
  description             = "Master credentials for Aurora global database ${local.name}"
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30

  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    engine   = "postgres"
    username = var.master_username
    password = random_password.master.result
    dbname   = local.database_name
    port     = 5432
    host     = aws_rds_cluster.primary.endpoint
  })
}

# ---------------------------------------------------------------------------
# Enhanced monitoring role (IAM is global; shared by both regions)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${local.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------------------------
# Parameter groups (identical in both regions)
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name}-cluster"
  family      = local.family
  description = "Cluster parameters for ${local.name}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-cluster"
  family      = local.family
  description = "Cluster parameters for ${local.name}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# CloudWatch log groups (pre-created so retention and encryption are ours)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "primary" {
  for_each          = toset(local.log_exports)
  name              = "/aws/rds/cluster/${local.name}-${var.primary_region}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  for_each          = toset(local.log_exports)
  name              = "/aws/rds/cluster/${local.name}-${var.secondary_region}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn
}

# ---------------------------------------------------------------------------
# Aurora Global Database
#
# Storage-level replication to the secondary region typically lags < 1s,
# meeting the "lose at most a few seconds of writes" objective. On a regional
# outage, the secondary is promoted with a managed global failover
# (aws rds failover-global-cluster --allow-data-loss) in minutes.
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = true
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = "${local.name}-${var.primary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  engine_mode               = "provisioned"
  database_name             = local.database_name
  master_username           = var.master_username
  master_password           = random_password.master.result
  port                      = 5432

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  delete_automated_backups     = false
  deletion_protection          = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.name}-${var.primary_region}-final"

  enabled_cloudwatch_logs_exports = local.log_exports
  apply_immediately               = false

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    # Version is driven by the global cluster; after a failover the roles
    # of the two clusters swap, which must not trigger replacement.
    ignore_changes = [
      engine_version,
      global_cluster_identifier,
      replication_source_identifier,
    ]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier                   = "${local.name}-${var.primary_region}-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.primary.id
  engine                       = aws_rds_cluster.primary.engine
  engine_version               = aws_rds_cluster.primary.engine_version
  instance_class               = var.instance_class
  db_subnet_group_name         = aws_db_subnet_group.primary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = false
  preferred_maintenance_window = var.preferred_maintenance_window
  promotion_tier               = count.index
  copy_tags_to_snapshot        = true

  monitoring_interval                   = 15
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7

  depends_on = [aws_iam_role_policy_attachment.monitoring]

  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.name}-${var.secondary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  engine_mode               = "provisioned"
  port                      = 5432

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  delete_automated_backups     = false
  deletion_protection          = true
  # A secondary cluster cannot take a final snapshot while it is a read-only
  # member of a global database; the primary retains the final snapshot.
  skip_final_snapshot = true

  enabled_cloudwatch_logs_exports = local.log_exports
  apply_immediately               = false

  # The secondary can only attach once the primary has a writer instance.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  lifecycle {
    ignore_changes = [
      engine_version,
      global_cluster_identifier,
      replication_source_identifier,
    ]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier                   = "${local.name}-${var.secondary_region}-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.secondary.id
  engine                       = aws_rds_cluster.secondary.engine
  engine_version               = aws_rds_cluster.secondary.engine_version
  instance_class               = var.instance_class
  db_subnet_group_name         = aws_db_subnet_group.secondary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = false
  preferred_maintenance_window = var.preferred_maintenance_window
  promotion_tier               = count.index
  copy_tags_to_snapshot        = true

  monitoring_interval                   = 15
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7

  depends_on = [aws_iam_role_policy_attachment.monitoring]

  lifecycle {
    ignore_changes = [engine_version]
  }
}

# ---------------------------------------------------------------------------
# Alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider            = aws.secondary
  alarm_name          = "${local.name}-global-replication-lag"
  alarm_description   = "Cross-region replication lag for ${local.name} exceeds the data-loss budget."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.replication_lag_alarm_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }
  alarm_actions = var.alarm_sns_topic_arns.secondary
  ok_actions    = var.alarm_sns_topic_arns.secondary
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  alarm_name          = "${local.name}-primary-cpu"
  alarm_description   = "Primary cluster CPU for ${local.name} is high."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }
  alarm_actions = var.alarm_sns_topic_arns.primary
  ok_actions    = var.alarm_sns_topic_arns.primary
}
