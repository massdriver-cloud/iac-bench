# ---------------------------------------------------------------------------
# Aurora PostgreSQL Global Database.
#
# One global database, two regional clusters:
#   - primary:   writer + in-region readers (in-region HA, ~seconds failover)
#   - secondary: warm readers on physical cross-region replication
#                (RPO ~1s; unplanned detach-and-promote RTO typically < 1 min)
#
# Regional failover is deliberately a human decision (see README runbook):
# automated cross-region failover on transient signals risks split-brain and
# data loss for payment workloads.
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = local.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be different regions."
    }
    precondition {
      condition     = startswith(var.primary_region, "us-") && startswith(var.secondary_region, "us-")
      error_message = "Both regions must be US regions (customer/payment data residency requirement)."
    }
  }
}

# ----------------------------- Primary region ------------------------------

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = local.primary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.global_cluster_identifier
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  engine_mode               = "provisioned"

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  # Break-glass admin only; applications use IAM auth. RDS generates the
  # password, stores it in Secrets Manager and rotates it.
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:30-sun:05:30"
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.name}-final"
  deletion_protection          = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]

  allow_major_version_upgrade = false
  apply_immediately           = false

  depends_on = [aws_cloudwatch_log_group.primary]

  tags = {
    Name = local.primary_cluster_id
    Role = "primary"
  }
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.primary_instance_count

  identifier         = "${local.name}-primary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version

  db_parameter_group_name    = aws_db_parameter_group.primary.name
  promotion_tier             = count.index
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  apply_immediately          = false

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  ca_cert_identifier = "rds-ca-rsa2048-g1"

  preferred_maintenance_window = "sun:04:30-sun:05:30"

  tags = {
    Name = "${local.name}-primary-${count.index + 1}"
    Role = count.index == 0 ? "writer-preferred" : "reader"
  }
}

# ---------------------------- Secondary region -----------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.global_cluster_identifier
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  engine_mode               = "provisioned"

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  # Master credentials replicate from the primary via the global database.
  iam_database_authentication_enabled = true

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  # Backup window must not overlap the primary's (global database requirement).
  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "06:00-07:00"
  preferred_maintenance_window = "sun:08:00-sun:09:00"
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.name}-dr-final"
  deletion_protection          = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]

  allow_major_version_upgrade = false
  apply_immediately           = false

  depends_on = [
    aws_cloudwatch_log_group.secondary,
    aws_rds_cluster_instance.primary,
  ]

  tags = {
    Name = local.secondary_cluster_id
    Role = "secondary"
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.name}-secondary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version

  db_parameter_group_name    = aws_db_parameter_group.secondary.name
  promotion_tier             = count.index
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  apply_immediately          = false

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  ca_cert_identifier = "rds-ca-rsa2048-g1"

  preferred_maintenance_window = "sun:08:00-sun:09:00"

  tags = {
    Name = "${local.name}-secondary-${count.index + 1}"
    Role = "dr-reader"
  }
}
