# Aurora Global Database: one writer cluster in the primary region and a warm,
# fully sized standby cluster in the secondary region, kept in sync by Aurora's
# storage-level replication (typically well under one second behind).
#
# If the primary region fails, the standby is promoted with a single managed
# failover call and the global writer endpoint follows it, so services
# reconnect without a configuration change.

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = local.engine
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

# ---------------------------------------------------------------------------
# Primary region
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.cluster_identifiers.primary}-${local.parameter_group_family}"
  family      = local.parameter_group_family
  description = "Cluster parameters for ${local.name} in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "immediate"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.cluster_identifiers.primary}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = local.cluster_identifiers.primary
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  database_name  = local.database_name
  port           = local.port

  master_username            = local.master_username
  master_password_wo         = jsondecode(ephemeral.aws_secretsmanager_secret_version.master.secret_string).password
  master_password_wo_version = var.master_password_version

  iam_database_authentication_enabled = true

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  enabled_cloudwatch_logs_exports = ["postgresql"]

  backup_retention_period   = var.backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${local.cluster_identifiers.primary}-final"

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    ignore_changes = [
      # Changes when the global database fails over or switches over.
      replication_source_identifier,
      # Engine upgrades are driven through aws_rds_global_cluster, which
      # upgrades every member cluster itself.
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

  db_subnet_group_name = aws_db_subnet_group.primary.name
  publicly_accessible  = false

  # Minor versions of a global database are upgraded together via
  # var.engine_version, never one instance at a time.
  auto_minor_version_upgrade = false

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary.arn
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.monitoring.arn

  copy_tags_to_snapshot = true

  lifecycle {
    ignore_changes = [engine_version]
  }
}

# ---------------------------------------------------------------------------
# Secondary region (warm standby, promoted on regional failover)
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.cluster_identifiers.secondary}-${local.parameter_group_family}"
  family      = local.parameter_group_family
  description = "Cluster parameters for ${local.name} in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "immediate"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.cluster_identifiers.secondary}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.cluster_identifiers.secondary
  global_cluster_identifier = aws_rds_global_cluster.this.id
  source_region             = var.primary_region

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  port           = local.port

  # No database name or master credentials here: a secondary cluster receives
  # them, with all other data, from the primary.

  iam_database_authentication_enabled = true

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.secondary.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  enabled_cloudwatch_logs_exports = ["postgresql"]

  backup_retention_period   = var.backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${local.cluster_identifiers.secondary}-final"

  # A secondary can only attach once the primary cluster has a writer.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  lifecycle {
    ignore_changes = [
      replication_source_identifier,
      engine_version,
    ]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.instances_per_region

  identifier         = "${local.cluster_identifiers.secondary}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.secondary.name
  publicly_accessible  = false

  auto_minor_version_upgrade = false

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary.arn
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.monitoring.arn

  copy_tags_to_snapshot = true

  lifecycle {
    ignore_changes = [engine_version]
  }
}
