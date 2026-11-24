###############################################################################
# Aurora PostgreSQL Global Database.
#
# DR design (the business bar: RPO seconds, RTO minutes on regional failure):
# - One global cluster spanning two US regions. Storage-level replication
#   typically keeps the secondary < 1 second behind (RPO ~ seconds).
# - The secondary region runs full-sized compute at all times, so a
#   cross-region failover ("aws rds failover-global-cluster") or a planned
#   switchover ("aws rds switchover-global-cluster") completes in ~minutes
#   with no provisioning delay. See README.md for the runbook.
#
# Data protection defaults (customer + payment data):
# - CMK encryption at rest in each region, TLS enforced in transit.
# - Master credentials generated/managed by RDS in Secrets Manager.
# - IAM database authentication for EKS workloads.
# - Deletion protection, 35-day PITR backups, final snapshot on destroy.
###############################################################################

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  # Never silently drop regional clusters (and their data) on destroy.
  force_destroy = false

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must differ: a second region is the whole point of the DR design."
    }
  }
}

# --------------------------- Primary region ---------------------------------

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier        = "${local.name}-primary"
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = "aurora-postgresql"
  engine_version = var.engine_version
  engine_mode    = "provisioned"
  port           = local.port
  database_name  = local.database_name

  # Credentials: RDS generates the password and stores/rotates it in
  # Secrets Manager under our CMK. No password ever enters state as a
  # variable or appears in code.
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-primary-final"

  allow_major_version_upgrade = false
  apply_immediately           = var.apply_immediately

  tags = {
    Name = "${local.name}-primary"
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

  db_subnet_group_name = aws_db_subnet_group.primary.name
  publicly_accessible  = false
  promotion_tier       = count.index

  monitoring_interval = var.enhanced_monitoring_interval
  monitoring_role_arn = var.enhanced_monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring.arn : null

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = aws_kms_key.primary.arn

  auto_minor_version_upgrade = true
  ca_cert_identifier         = "rds-ca-rsa2048-g1"
  apply_immediately          = var.apply_immediately

  tags = {
    Name = "${local.name}-primary-${count.index + 1}"
    Role = count.index == 0 ? "writer" : "reader"
  }

  depends_on = [aws_iam_role_policy_attachment.enhanced_monitoring]
}

# --------------------------- Secondary region -------------------------------
# No master_username / manage_master_user_password / database_name here:
# credentials and data replicate from the primary via the global database.

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.name}-secondary"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  source_region             = var.primary_region

  engine         = "aurora-postgresql"
  engine_version = var.engine_version
  engine_mode    = "provisioned"
  port           = local.port

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = "04:00-05:00"
  preferred_maintenance_window = "sun:06:00-sun:07:00"
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection = var.deletion_protection
  # The authoritative final snapshot is taken from the primary cluster;
  # a secondary-cluster snapshot of replicated storage adds nothing.
  skip_final_snapshot = true

  allow_major_version_upgrade = false
  apply_immediately           = var.apply_immediately

  tags = {
    Name = "${local.name}-secondary"
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

  db_subnet_group_name = aws_db_subnet_group.secondary.name
  publicly_accessible  = false
  promotion_tier       = count.index

  monitoring_interval = var.enhanced_monitoring_interval
  monitoring_role_arn = var.enhanced_monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring.arn : null

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn

  auto_minor_version_upgrade = true
  ca_cert_identifier         = "rds-ca-rsa2048-g1"
  apply_immediately          = var.apply_immediately

  tags = {
    Name = "${local.name}-secondary-${count.index + 1}"
    Role = "reader"
  }

  depends_on = [aws_iam_role_policy_attachment.enhanced_monitoring]
}

# --------------------------- Parameter groups -------------------------------
# TLS is mandatory (rds.force_ssl) - payment data never crosses the network
# in cleartext. Connection logging gives a basic audit trail.

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name_prefix = "${local.name}-cluster-"
  family      = local.parameter_group_family
  description = "${local.name} Aurora PostgreSQL cluster parameters (${var.primary_region})"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  tags = {
    Name = "${local.name}-cluster"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.name}-cluster-"
  family      = local.parameter_group_family
  description = "${local.name} Aurora PostgreSQL cluster parameters (${var.secondary_region})"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }

  tags = {
    Name = "${local.name}-cluster"
  }

  lifecycle {
    create_before_destroy = true
  }
}
