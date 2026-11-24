# ---------------------------------------------------------------------------
# Cluster parameter groups (regional resources, one per region)
#
# rds.force_ssl = 1 makes TLS mandatory for every connection - these
# databases hold customer and payment data, and IAM database
# authentication tokens are used over TLS as well.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name}-cluster-params"
  family      = local.parameter_group_family
  description = "Cluster parameters for the ${local.name} Aurora PostgreSQL cluster (${var.primary_region})."

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-cluster-params"
  family      = local.parameter_group_family
  description = "Cluster parameters for the ${local.name} Aurora PostgreSQL cluster (${var.secondary_region})."

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }
}

# ---------------------------------------------------------------------------
# Regional clusters
# ---------------------------------------------------------------------------

# The primary cluster owns the writer endpoint and the master credentials.
resource "aws_rds_cluster" "primary" {
  cluster_identifier = local.name
  engine             = local.engine
  engine_version     = local.engine_version
  database_name      = local.database_name
  master_username    = var.master_username
  master_password    = random_password.master.result
  port               = var.port

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary.id]

  global_cluster_identifier = aws_rds_global_cluster.this.id

  # Encryption at rest is not optional for customer and payment data.
  storage_encrypted = true
  storage_type      = var.storage_type
  kms_key_id        = var.storage_kms_key_id

  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  backup_retention_period      = local.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection             = local.deletion_protection
  skip_final_snapshot             = local.skip_final_snapshot
  final_snapshot_identifier       = local.skip_final_snapshot ? null : "${local.name}-final"
  apply_immediately               = var.apply_immediately
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
}

# The secondary cluster is an always-on warm standby in the second region. It
# replicates the primary with sub-second typical lag, serves local reads for
# services running there, and is promoted on regional failover. Credentials,
# storage encryption, storage type and the initial database are inherited
# from the primary through the global database, so none of them may be set
# here.
resource "aws_rds_cluster" "secondary" {
  provider           = aws.secondary
  cluster_identifier = "${local.name}-${var.secondary_region}"
  engine             = local.engine
  engine_version     = local.engine_version

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.secondary.id]

  global_cluster_identifier = aws_rds_global_cluster.this.id

  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  backup_retention_period      = local.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection             = local.deletion_protection
  skip_final_snapshot             = local.skip_final_snapshot
  final_snapshot_identifier       = local.skip_final_snapshot ? null : "${local.name}-${var.secondary_region}-final"
  apply_immediately               = var.apply_immediately
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  # A global database needs its primary before a secondary can join, and on
  # destroy the secondary must leave the global database first.
  depends_on = [aws_rds_cluster.primary]
}
