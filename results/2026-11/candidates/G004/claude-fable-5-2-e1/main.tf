###############################################################################
# Aurora PostgreSQL global database
#
#   primary region                      secondary (DR) region
#   +--------------------------+        +--------------------------+
#   | cluster (writer)         |  ---→  | cluster (read-only copy) |
#   |  N instances, multi-AZ   |  <1s   |  N instances, multi-AZ   |
#   +--------------------------+  lag   +--------------------------+
#
# Storage-level replication keeps the DR region typically under a second
# behind. The DR cluster runs the same number and size of instances as the
# primary, so promoting it is a single managed operation that completes in
# minutes and it can take full production load straight away.
###############################################################################

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = local.name
  engine                    = local.engine
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    precondition {
      condition     = data.aws_rds_engine_version.primary.supports_global_databases && data.aws_rds_engine_version.secondary.supports_global_databases
      error_message = "Aurora PostgreSQL ${var.engine_version} does not support global databases in ${var.primary_region} and ${var.secondary_region}."
    }
  }
}

###############################################################################
# Cluster parameter groups (identical in both regions)
###############################################################################

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name        = "${local.cluster_ids.primary}-pg${local.engine_major_version}"
  family      = local.parameter_group_family
  description = "Security and audit settings for ${local.cluster_ids.primary}"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.cluster_ids.secondary}-pg${local.engine_major_version}"
  family      = local.parameter_group_family
  description = "Security and audit settings for ${local.cluster_ids.secondary}"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Primary region
###############################################################################

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = local.cluster_ids.primary
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  database_name  = aws_rds_global_cluster.this.database_name
  port           = local.port

  master_username            = var.master_username
  master_password_wo         = jsondecode(ephemeral.aws_secretsmanager_secret_version.master.secret_string).password
  master_password_wo_version = var.master_password_version

  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.db_primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "07:00-08:00"         # UTC; night-time across US time zones
  preferred_maintenance_window = "sun:08:30-sun:09:30" # UTC
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.cluster_ids.primary}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  apply_immediately = false

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    ignore_changes = [
      # Engine upgrades are driven through the global cluster.
      engine_version,
      # Set by Aurora and changes when regions swap roles.
      replication_source_identifier,
    ]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  for_each = local.instance_keys

  identifier         = "${local.cluster_ids.primary}-${each.key}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  instance_class     = data.aws_rds_orderable_db_instance.primary.instance_class

  db_subnet_group_name = aws_db_subnet_group.primary.name
  publicly_accessible  = false
  ca_cert_identifier   = "rds-ca-rsa2048-g1"

  # All instances are equal failover candidates.
  promotion_tier = 1

  # Version changes are made deliberately through var.engine_version.
  auto_minor_version_upgrade = false
  apply_immediately          = false
  copy_tags_to_snapshot      = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}

###############################################################################
# Secondary (DR) region
###############################################################################

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.cluster_ids.secondary
  global_cluster_identifier = aws_rds_global_cluster.this.id
  source_region             = var.primary_region

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  port           = local.port

  # No database name or master credentials here: they replicate from the
  # primary along with the data.

  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.enable_write_forwarding

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.db_secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "07:00-08:00"         # UTC
  preferred_maintenance_window = "sat:08:30-sat:09:30" # UTC; a different day from the primary
  copy_tags_to_snapshot        = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.cluster_ids.secondary}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  apply_immediately = false

  # A region can only join the global database once the primary has a running
  # writer instance.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  lifecycle {
    ignore_changes = [
      engine_version,
      replication_source_identifier,
    ]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  for_each = local.instance_keys

  identifier         = "${local.cluster_ids.secondary}-${each.key}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  instance_class     = data.aws_rds_orderable_db_instance.secondary.instance_class

  db_subnet_group_name = aws_db_subnet_group.secondary.name
  publicly_accessible  = false
  ca_cert_identifier   = "rds-ca-rsa2048-g1"

  promotion_tier = 1

  auto_minor_version_upgrade = false
  apply_immediately          = false
  copy_tags_to_snapshot      = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}
