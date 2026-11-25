# Aurora PostgreSQL Global Database: one primary regional cluster that takes
# writes, and one secondary regional cluster that replicates storage-level
# (typically < 1 second, alarmed at 5 seconds) and can be promoted to primary.

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
  force_destroy             = false

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be different regions."
    }
  }
}

# ---------------------------------------------------------------------------
# Parameter groups. Same settings in both regions so a promoted cluster
# behaves identically to the one it replaced.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name        = "${local.primary_cluster_id}-params"
  family      = local.engine_family
  description = "Parameters for ${local.primary_cluster_id}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "idle_in_transaction_session_timeout"
    value        = "300000"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_lock_waits"
    value        = "1"
    apply_method = "immediate"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-params"
  family      = local.engine_family
  description = "Parameters for ${local.secondary_cluster_id}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "idle_in_transaction_session_timeout"
    value        = "300000"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_lock_waits"
    value        = "1"
    apply_method = "immediate"
  }
}

# ---------------------------------------------------------------------------
# Primary regional cluster (writer).
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = local.primary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  engine_mode               = "provisioned"
  database_name             = var.database_name

  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.primary_cluster_id}-final"

  depends_on = [aws_cloudwatch_log_group.primary_postgresql]
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.instance_count_per_region

  identifier         = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  instance_class     = var.instance_class
  promotion_tier     = count.index

  db_subnet_group_name       = aws_db_subnet_group.primary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
}

# ---------------------------------------------------------------------------
# Secondary regional cluster (read-only until promoted). It takes no master
# user and no database name: both come from the global cluster.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  engine_mode               = "provisioned"

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.secondary_cluster_id}-final"

  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary_postgresql,
  ]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.instance_count_per_region

  identifier         = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  instance_class     = var.instance_class
  promotion_tier     = count.index

  db_subnet_group_name       = aws_db_subnet_group.secondary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
}
